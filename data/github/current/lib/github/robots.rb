# typed: true
# frozen_string_literal: true

module ::GitHub
  # List of well-known crawlers manually compiled over many years
  # by inspecting user-agent headers from requests logs.
  ROBOTS = [
    "360Spider",
    "AddSearchBot",
    "AhrefsBot",
    "AhrefsSiteAudit",
    "Amazonbot",
    "Applebot",
    "Archive Team",
    "archive.org_bot",
    "AwarioBot",
    "Baiduspider",
    "Barkrowler",
    "bingbot",
    "BLEXBot",
    "botify",
    "Bytespider",
    "CCBot",
    "ChatGPT-User",
    "coccoc",
    "Coveobot",
    "DataForSeoBot",
    "Daumoa",
    "Discordbot",
    "Diffbot",
    "digitalshadowsbot",
    "dotbot",
    "duckduckbot",
    "EtaoSpider",
    "ev-crawler",
    "Exabot",
    "FFZBot",
    "FriendlyCrawler",
    "Googlebot",
    "GoogleOther",
    "Google-Safety",
    "GPTBot",
    "HTTrack",
    "HubSpot Crawler",
    "ia_archiver",
    "ImagesiftBot",
    "IntuitGSACrawler",
    "KeybaseBot",
    "Linespider",
    "MagiBot",
    "Mail.RU_Bot",
    "MJ12bot",
    "MojeekBot",
    "monitoring360bot",
    "msnbot",
    "naverbot",
    "Neevabot",
    "NIXStatsbot",
    "PetalBot",
    "Pinterestbot",
    "redditbot",
    "red-app-gsa-p-one",
    "rogerbot",
    "SandDollar",
    "SeekportBot",
    "SemanticScholarBot",
    "SemrushBot",
    "seznambot",
    "SiteAuditBot",
    "Slurp",
    "startmebot",
    "Swiftbot",
    "Telefonica",
    "teoma",
    "ThinkBot",
    "trendictionbot",
    "Twitterbot",
    "UptimeRobot",
    "Yandex",
    "Yeti",
    "YioopBot",
    "YisouSpider",
    "ZumBot",
  ]
  # NOTE: dotbot and rogerbot belong to moz.com
  KNOWN_ROBOTS_REGEX = Regexp.union(ROBOTS)

  # In general, user-agent strings for requests made by crawlers include
  # either a URL or an email address by which site owners can learn more
  # about the craweler or get in touch with the crawelr's owner. And
  # normally, user-agent strings for requests made by browsers don't
  # include a URL or an email address.
  #
  # So, we can use this difference to auto-detect crawlers. We detect
  # whether the user-agent string includes an HTTP URL or email address,
  # but don't do anything with the URL or email address. Crawlers detected
  # this way have their "type" set to "other" since we don't attempt
  # to parse the user-agent string to find a name for the crawler.

  # A simple regex for detecting email addresses like foo-bar@baz.quux. The
  # regex isn't a good parser for email addresses since many addresses will
  # have more parts, e.g. foo+bar@baz.quux, but it will match a substring
  # of the address which is enough for detection, e.g. bar@baz.quux.
  EMAIL_REGEX = /\w+@\w+(\.\w+)*(\.[a-z]{2,})/i

  # A simple regex for detecting HTTP URLs. Again, we don't parse the whole
  # URL for parts, but just assume there's a whole URL if we find the HTTP(S)
  # prefix.
  URL_REGEX = /https?:\/\//i

  # Regex for auto-detecting crawlers by detecting whether the user-agent string
  # includes a well-known crawler name, an email, or an HTTP URL.
  AUTODETECT_ROBOT_REGEX = Regexp.union(KNOWN_ROBOTS_REGEX, EMAIL_REGEX, URL_REGEX)

  def self.robot?(useragent)
    !!useragent.match?(AUTODETECT_ROBOT_REGEX)
  end
end
