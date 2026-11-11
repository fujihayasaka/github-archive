# frozen_string_literal: true

Mime::Type.register_alias "text/plain", :diff
Mime::Type.register_alias "text/plain", :patch
Mime::Type.register_alias "text/plain", :keys
Mime::Type.register_alias "text/plain", :sigkeys
Mime::Type.register_alias "application/json", :contribs
Mime::Type.register "application/octet-stream", :octet_stream
Mime::Type.register "image/svg+xml", :svg
Mime::Type.register "text/fragment+html", :html_fragment
Mime::Type.register_alias "text/html", :iphone
Mime::Type.register_alias "application/vnd.github.v3+json", :github_v3
Mime::Type.register_alias "application/vnd.octocat+json", :octocat_json
Mime::Type.register_alias "application/vnd.octocat+text", :octocat_text
Mime::Type.register_alias "text/html", :pibb # Used by Gist embeds
Mime::Type.register_alias "text/plain", :toml
Mime::Type.register "application/sarif+json", :sarif
Mime::Type.register "application/zip", :zip
Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream
# added upstream here: https://github.com/rails/rails/commit/3fb706eb17e972507e101113df16df0a12ad3c9f#diff-eba0374aa6f44e0949a67b4c2ac789497858b545a818a58ebd0878ed6a46e0e9R16
# causing breaking changes to our responses
Mime::Type.unregister :md
