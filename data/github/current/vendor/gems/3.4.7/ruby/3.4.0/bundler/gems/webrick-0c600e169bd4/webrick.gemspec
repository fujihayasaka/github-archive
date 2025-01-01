# -*- encoding: utf-8 -*-
# stub: webrick 1.8.1 ruby lib

Gem::Specification.new do |s|
  s.name = "webrick".freeze
  s.version = "1.8.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/ruby/webrick/issues" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["TAKAHASHI Masayoshi".freeze, "GOTOU YUUZOU".freeze, "Eric Wong".freeze]
  s.date = "1980-01-02"
  s.description = "WEBrick is an HTTP server toolkit that can be configured as an HTTPS server, a proxy server, and a virtual-host server.".freeze
  s.email = [nil, nil, "normal@ruby-lang.org".freeze]
  s.files = ["Gemfile".freeze, "LICENSE.txt".freeze, "README.md".freeze, "Rakefile".freeze, "lib/webrick.rb".freeze, "lib/webrick/accesslog.rb".freeze, "lib/webrick/cgi.rb".freeze, "lib/webrick/compat.rb".freeze, "lib/webrick/config.rb".freeze, "lib/webrick/cookie.rb".freeze, "lib/webrick/htmlutils.rb".freeze, "lib/webrick/httpauth.rb".freeze, "lib/webrick/httpauth/authenticator.rb".freeze, "lib/webrick/httpauth/basicauth.rb".freeze, "lib/webrick/httpauth/digestauth.rb".freeze, "lib/webrick/httpauth/htdigest.rb".freeze, "lib/webrick/httpauth/htgroup.rb".freeze, "lib/webrick/httpauth/htpasswd.rb".freeze, "lib/webrick/httpauth/userdb.rb".freeze, "lib/webrick/httpproxy.rb".freeze, "lib/webrick/httprequest.rb".freeze, "lib/webrick/httpresponse.rb".freeze, "lib/webrick/https.rb".freeze, "lib/webrick/httpserver.rb".freeze, "lib/webrick/httpservlet.rb".freeze, "lib/webrick/httpservlet/abstract.rb".freeze, "lib/webrick/httpservlet/cgi_runner.rb".freeze, "lib/webrick/httpservlet/cgihandler.rb".freeze, "lib/webrick/httpservlet/erbhandler.rb".freeze, "lib/webrick/httpservlet/filehandler.rb".freeze, "lib/webrick/httpservlet/prochandler.rb".freeze, "lib/webrick/httpstatus.rb".freeze, "lib/webrick/httputils.rb".freeze, "lib/webrick/httpversion.rb".freeze, "lib/webrick/log.rb".freeze, "lib/webrick/server.rb".freeze, "lib/webrick/ssl.rb".freeze, "lib/webrick/utils.rb".freeze, "lib/webrick/version.rb".freeze, "webrick.gemspec".freeze]
  s.homepage = "https://github.com/ruby/webrick".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.4.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "HTTP server toolkit".freeze

  s.installed_by_version = "3.6.9".freeze
end
