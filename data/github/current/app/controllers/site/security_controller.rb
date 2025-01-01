# typed: true
# frozen_string_literal: true

class Site::SecurityController < Site::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:txt]

  SECURITY_TXT_EXPIRES = 30.days

  def txt # rubocop:todo GitHub/UseRestfulActions
    render plain: <<~EOF
      Contact: https://hackerone.com/github
      Acknowledgments: https://hackerone.com/github/hacktivity
      Preferred-Languages: en
      Canonical: https://github.com/.well-known/security.txt
      Policy: https://bounty.github.com
      Hiring: https://github.careers
      Expires: #{(Time.now.utc + SECURITY_TXT_EXPIRES).strftime("%FT%Tz")}
    EOF
  end
end
