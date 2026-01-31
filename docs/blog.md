---
layout: default
title: Blog
permalink: /blog/
---

# Infrastructure Log

Daily updates from the Lanmine infrastructure, automatically generated.

---

{% for post in site.posts %}
## [{{ post.title }}]({{ post.url | relative_url }})
<small>{{ post.date | date: "%B %d, %Y" }}</small>

{{ post.excerpt | strip_html | truncatewords: 75 }}

---
{% endfor %}

{% if site.posts.size == 0 %}
*No posts yet. Daily updates will appear here automatically.*
{% endif %}
