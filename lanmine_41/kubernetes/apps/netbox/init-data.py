#!/usr/bin/env python3
"""
NetBox Initialization Script
Populates NetBox with initial switch inventory from Ansible inventory.
"""

import os
import sys
import yaml
import requests
from pathlib import Path

# Configuration
NETBOX_URL = "https://netbox.lionfish-caiman.ts.net"
NETBOX_TOKEN = os.getenv("NETBOX_TOKEN")
INVENTORY_PATH = "ansible/inventory/switches.yml"

# Verify token
if not NETBOX_TOKEN:
    print("Error: NETBOX_TOKEN environment variable not set")
    print("Run: export NETBOX_TOKEN=$(vault kv get -field=superuser_api_token secret/infrastructure/netbox)")
    sys.exit(1)

# Headers for API requests
HEADERS = {
    "Authorization": f"Token {NETBOX_TOKEN}",
    "Content-Type": "application/json",
    "Accept": "application/json",
}

def api_get(endpoint):
    """GET request to NetBox API"""
    url = f"{NETBOX_URL}/api/{endpoint}"
    response = requests.get(url, headers=HEADERS, verify=True)
    response.raise_for_status()
    return response.json()

def api_post(endpoint, data):
    """POST request to NetBox API"""
    url = f"{NETBOX_URL}/api/{endpoint}"
    response = requests.post(url, headers=HEADERS, json=data, verify=True)
    response.raise_for_status()
    return response.json()

def get_or_create_site(name, slug):
    """Get or create site"""
    try:
        results = api_get(f"dcim/sites/?slug={slug}")
        if results["count"] > 0:
            print(f"  Site '{name}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating site: {name}")
    return api_post("dcim/sites/", {
        "name": name,
        "slug": slug,
        "status": "active",
    })

def get_or_create_manufacturer(name, slug):
    """Get or create manufacturer"""
    try:
        results = api_get(f"dcim/manufacturers/?slug={slug}")
        if results["count"] > 0:
            print(f"  Manufacturer '{name}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating manufacturer: {name}")
    return api_post("dcim/manufacturers/", {
        "name": name,
        "slug": slug,
    })

def get_or_create_device_type(model, slug, manufacturer_id):
    """Get or create device type"""
    try:
        results = api_get(f"dcim/device-types/?slug={slug}")
        if results["count"] > 0:
            print(f"  Device type '{model}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating device type: {model}")
    return api_post("dcim/device-types/", {
        "manufacturer": manufacturer_id,
        "model": model,
        "slug": slug,
    })

def get_or_create_device_role(name, slug, color):
    """Get or create device role"""
    try:
        results = api_get(f"dcim/device-roles/?slug={slug}")
        if results["count"] > 0:
            print(f"  Device role '{name}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating device role: {name}")
    return api_post("dcim/device-roles/", {
        "name": name,
        "slug": slug,
        "color": color,
    })

def get_or_create_device(hostname, site_id, device_type_id, role_id, serial):
    """Get or create device"""
    try:
        results = api_get(f"dcim/devices/?name={hostname}")
        if results["count"] > 0:
            print(f"  Device '{hostname}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating device: {hostname}")
    return api_post("dcim/devices/", {
        "name": hostname,
        "device_type": device_type_id,
        "role": role_id,
        "site": site_id,
        "serial": serial,
        "status": "active",
    })

def get_or_create_interface(device_id, name, interface_type):
    """Get or create interface"""
    try:
        results = api_get(f"dcim/interfaces/?device_id={device_id}&name={name}")
        if results["count"] > 0:
            print(f"  Interface '{name}' already exists")
            return results["results"][0]
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating interface: {name}")
    return api_post("dcim/interfaces/", {
        "device": device_id,
        "name": name,
        "type": interface_type,
    })

def get_or_create_ip_address(address, interface_id):
    """Get or create IP address and assign to interface"""
    try:
        results = api_get(f"ipam/ip-addresses/?address={address}")
        if results["count"] > 0:
            print(f"  IP address '{address}' already exists")
            ip = results["results"][0]
            # Update interface assignment if needed
            if not ip.get("assigned_object") or ip["assigned_object"]["id"] != interface_id:
                print(f"  Updating IP address assignment")
                api_post(f"ipam/ip-addresses/{ip['id']}/", {
                    "address": address,
                    "assigned_object_type": "dcim.interface",
                    "assigned_object_id": interface_id,
                })
            return ip
    except requests.exceptions.HTTPError:
        pass

    print(f"  Creating IP address: {address}")
    return api_post("ipam/ip-addresses/", {
        "address": address,
        "assigned_object_type": "dcim.interface",
        "assigned_object_id": interface_id,
    })

def set_primary_ip(device_id, ip_id):
    """Set primary IP for device"""
    print(f"  Setting primary IP")
    url = f"{NETBOX_URL}/api/dcim/devices/{device_id}/"
    response = requests.patch(
        url,
        headers=HEADERS,
        json={"primary_ip4": ip_id},
        verify=True
    )
    response.raise_for_status()
    return response.json()

def load_inventory():
    """Load switch inventory from Ansible"""
    # Find repo root (3 levels up from kubernetes/apps/netbox/)
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent.parent.parent
    inventory_file = repo_root / INVENTORY_PATH

    if not inventory_file.exists():
        print(f"Error: Inventory file not found: {inventory_file}")
        sys.exit(1)

    with open(inventory_file, 'r') as f:
        data = yaml.safe_load(f)

    return data.get("switches", [])

def main():
    print("NetBox Initialization Script")
    print("=" * 50)

    # Load inventory
    print("\nLoading switch inventory...")
    switches = load_inventory()
    print(f"Found {len(switches)} switch(es)")

    # Create base objects
    print("\nCreating/verifying base objects...")
    site = get_or_create_site("Lanmine Datacenter", "lanmine-dc")
    cisco = get_or_create_manufacturer("Cisco", "cisco")

    # Process each switch
    for switch in switches:
        print(f"\nProcessing switch: {switch['hostname']}")

        # Create device type
        device_type = get_or_create_device_type(
            switch['model'],
            switch['model'],
            cisco['id']
        )

        # Create device role
        role_colors = {
            "core": "2196f3",    # blue
            "access": "4caf50",  # green
            "edge": "ff9800",    # orange
        }
        role = get_or_create_device_role(
            switch['role'],
            switch['role'],
            role_colors.get(switch['role'], "607d8b")
        )

        # Create device
        device = get_or_create_device(
            switch['hostname'],
            site['id'],
            device_type['id'],
            role['id'],
            switch['serial']
        )

        # Create management interface
        interface = get_or_create_interface(
            device['id'],
            "Vlan99",
            "virtual"
        )

        # Create IP address
        mgmt_ip = f"{switch['mgmt_ip']}/24"
        ip = get_or_create_ip_address(mgmt_ip, interface['id'])

        # Set primary IP
        set_primary_ip(device['id'], ip['id'])

        print(f"  ✓ {switch['hostname']} registered successfully")

    print("\n" + "=" * 50)
    print("Initialization complete!")
    print(f"\nView devices: {NETBOX_URL}/dcim/devices/")

if __name__ == "__main__":
    main()
