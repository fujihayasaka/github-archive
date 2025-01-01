# typed: true
# frozen_string_literal: true
module Spam
  class SpammyReasonNormalizer
    attr_accessor :classifier_type, :classifier_id, :subject, :analyst, :matched_regexp, :spammy

    def initialize(spammy_reason)
      meta_data           = extract_from_spammy_reason(spammy_reason)
      @matched_regexp     = meta_data[:matched_regexp]
      @analyst            = meta_data[:analyst]
      @classifier_type    = meta_data[:classifier_type]
      @classifier_id      = get_classifier_id(**meta_data)
      @subject            = normalize_subject(meta_data[:subject])
    end

    def payload
      payload = {}
      payload[:subject]                = subject
      payload[:spammy_classification]  = spammy_classification
      payload[:spammy_classifier_type] = classifier_type
      payload[:spammy_classifier_id]   = classifier_id
      payload[:matched_regexp]         = matched_regexp.inspect if matched_regexp
      payload
    end

    private

    def spammy_classification
      if %w[spam-datasource spam-pattern].include?(classifier_type)
        "#{classifier_type}"
      else
        "#{classifier_type}-#{classifier_id}"
      end
    end

    SUBJECTS = Regexp.new([
      "pages",
      "issuecomment",
      "issue",
      "commit comment",
      "pr review comment",
      "gist comment",
      "gist",
      "repo",
      "profile",
      "user email",
      "wiki",
      "account",
    ].join("|"), Regexp::IGNORECASE)

    SUBJECT = /(#{SUBJECTS})[\w\s]*/

    # Extracts metadata from the user.spammy_reason field.
    # This method creates normalized and structured metadata
    # about why a user was marked as spammy
    #
    # Returns a Hash. ex:
    # {
    #   classifier_type: "regex",
    #   subject: "pages",
    #   reason: "failed pages test",
    #   analyst: "erebor",
    #   matched_regexp: /Pages spam/,
    # }
    def extract_from_spammy_reason(reason)
      analyst_login = nil

      result = case reason
      when /(.*)[\w]?by @([^\s]+)(\z| \[octocat approved\])/
        sub_reason = $1
        analyst_login = $2
        analyst_subject, analyst_reason = case sub_reason
        when /Profile\/login spam/                then ["profile", "profile/login spam"]
        when /Repo\/Issue spam/i                  then ["repo", "repo/issue spam"]
        when /Comment spam \(Gist\/Issue\/etc\)/i then ["gist-comments", "gist/issue comment spam"]
        when /Gist spam/i                         then ["gist", "gist spam"]
        when /Wiki spam/i                         then ["wiki", "wiki spam"]
        when /Star spammer/i                      then ["star", "star spammer"]
        when /Multiple accounts/i                 then ["account", "extra account"]
        when /Bot farmer/i                        then ["account", "bot farmer"]
        when /Fake account spam/i                 then ["account", "fake account"]
        when /copycat/i                then %w[account copycat]
        when /dupe account/i           then %w[account copycat]
        when /duplicate account/i      then ["account", "extra account"]
        when /extra account/i          then ["account", "extra account"]
        when /extra free account/i     then ["account", "extra account"]
        when /fake account/i           then ["account", "fake account"]
        when /gist.*report as abuse/i  then ["gist", "reported as abuse"]
        when /gist spam.*munch gists/i then ["gist", "munch gists"]
        when /gist spam/i              then ["gist", "gist spammer"]
        when /gist comments spam/i     then ["gist-comments", "gist comments spam"]
        when /issue spam/i             then ["issue", "issue spam"]
        when /issuecomment/i           then ["issue-comment", "issue comment spam"]
        when /profile spam/i           then ["account", "profile spam"]
        when /repo spam/i              then ["repo", "repo spam"]
        when /spammy repo/i            then ["repo", "repo spam"]
        when /user email spam/i        then ["email", "email spam"]
        when /user login/i             then %w[account login]
        when /bitcoin/i                then ["oauth", "bitcoin miner"]
        when /book.*spammer/i          then ["gist", "book spammer"]
        when /mining via ci/i          then ["oauth", "bitcoin miner"]
        when /flagged by staff/i       then ["oauth", "flagged by staff"]
        when /gmail gist/i             then ["gist", "gmail gist"]
        when /gmail account/i          then ["account", "gmail account"]
        when /gmail flood/i            then ["account", "gmail account"]
        when /malware/i                then %w[gist malware]
        when /porn site on pages/i     then %w[pages porn]
        when /org.*spammy/i            then %w[org spammy]
        when /star spammer/i           then ["star", "star spammer"]
        when /profile\/login/i         then ["profile", "profile/login spam"]
        when /student pack/i           then ["student-pack", "student pack spammer"]
        else
          ["unknown", sub_reason.to_s[0..24]]
        end

        ["analyst", analyst_subject, analyst_reason]
      when /\AProbable star spammer\z/                                  then ["orion-classifier", "star", "star spammer"]
      when /\d+ of \d+ recent users at IP [\d\.]+ are spammy/           then ["regexp", "ip", "spammy neighbors"]
      when /(update|create) Wiki page in < 1 hour/                      then ["regexp", "wiki", "#{$1}d within 1 hour after user creation"]
      when /Attempted to create Wiki spam on/                           then ["regexp", "wiki", "spammy content on wiki create"]
      when /Attempted an update w\/Wiki spam on/                        then ["regexp", "wiki", "spammy content on wiki update"]
      when /User email spam \(.* had \d+ obfuscated duplicates\)/       then ["regexp", "user-email", "obfuscated duplicates"]
      when /User email spam \(.+ matched pattern (.*)\)/                then ["spam-datasource", "user-email", $1]
      when /Issue spam .* : SpamPattern (\d+).*(,|$)/                   then ["spam-pattern", "issue", $1]
      when /Issue spam .* : (body|title|tech support spammer).*(,|$)/   then ["regexp", "issue", $1]
      when /Repo spam .* : SpamPattern (\d+)/                           then ["spam-pattern", "repo", $1]
      when /Commit comment spam.*\): SpamPattern (\d+)/                 then ["spam-pattern", "commit-comment", $1]
      when /User account spam \(.*SpamPattern (\d+).*/                  then ["spam-pattern", "account", $1]
      when /User account spam \((.*)\;.*/                               then ["regexp", "account", $1]
      when /User account spam \((.*)\).*/                               then ["regexp", "account", $1]
      when /Gist spam \(user's IP of/                                   then ["regexp", "gist", "user ip is blacklisted"]
      when /Repo spam bot/                                              then ["regexp", "repo", "created within 15s after user creation"]
      when /Repo (name|description|homepage) spam/                      then ["regexp", "repo", "blacklisted repo #{$1}"]
      when /Pages spam/                                                 then ["regexp", "pages", "failed pages test"]
      when /Blacklisted payment method/                                 then %w[regexp payment-method blacklisted]
      when /IP ([\d\.]+) was on auto-flag status/                       then ["regexp", "ip", "IP was on auto-flag status"]
      when /\A(Tech Support Wiki spam).* on #{GitHub.url}/              then ["regexp", "wiki", $1]
      when /\A(Solahart Wiki spam).* on #{GitHub.url}/                  then ["regexp", "wiki", $1]
      when /\AContent matched Wiki pattern (.*) on #{GitHub.url}/       then ["spam-datasource", "wiki", $1]
        #pattern location SpamChecker#test_wiki_content
      when /#{SUBJECT} \(.*Mr\. Bayes said spam.*/                      then ["nbayes", $1, "nbayes classified spammy"]
      when /#{SUBJECT} \(.*SpamPattern (\d+).*/                         then ["spam-pattern", $1, $2]
      when /#{SUBJECT} \(excessive duplicate links to same URL.*/       then ["regexp", $1, "excessive duplicate links to same URL"]
      when /#{SUBJECT} \(Compound login.*/                              then ["regexp", $1, "compound login"]
      when /#{SUBJECT} \(blob data matched current pattern \((.*)\),.*/ then ["spam-datasource", $1, $2]
      when /#{SUBJECT} \(.*\) : (body|title).*(,|$)/                    then ["regexp", $1, $2]
      when /#{SUBJECT} \(.*\) : SpamPattern (\d+).*(,|$)/               then ["spam-pattern", $1, $2]
      when /#{SUBJECT}.* spam \(id \d+\): content.*/                    then ["regexp", $1, "content"]
      when /#{SUBJECT}.* spam \(id \d+\): posting.*/                    then ["regexp", $1, "posting"]
      when /#{SUBJECT}.* spam \(id \d+\): description.*/                then ["regexp", $1, "description"]
      when /#{SUBJECT}.* spam \(id \d+\): single path name.*/           then ["regexp", $1, "single path name"]
      when /#{SUBJECT}.* spam \(id \d+\): comment has too many links.*/ then ["regexp", $1, "excessive duplicate links to same URL"]
      when /#{SUBJECT}.* spam \(id \d+\): (.*?)(, |$)/                  then ["regexp", $1, $2]
        # Ex SpamChecker#test_comment #hack for now to normalize string. Todo normallize upstream cod
      when /#{SUBJECT} \(([\w\s]+), .*/                                 then ["regexp", $1, $2]
        # Ex Gist spam (blob content, id: 76184926, url: [secret], path: FFBEAutoZ20b.lu)
      when /#{SUBJECT} spam \((.*?)(,.*|\)\z)/                          then ["regexp", $1, $2]
        # Ex User account spam (Fake login/email)
      else
        ["unclassified", "unknown", reason.to_s[0..24]] # This should be empty. If not, then these should be classified
      end

      {
        classifier_type: result[0],
        subject: result[1] == "user" ? "account" : result[1],
        reason: result[2],
        analyst: analyst_login,
        matched_regexp: Regexp.last_match&.regexp,
      }
    end

    def normalize_subject(subject)
      return "issue-comment" if subject =~ /issuecomment/i # special case this to add hyphen
      subject && subject.downcase.gsub(" ", "-")
    end

    # Takes a classifier_type, subject, and reason.
    # Returns the classification id.
    #
    # returns FIXNUM
    def get_classifier_id(classifier_type:, subject:, reason:, **_)
      id = case classifier_type
      when "spam-datasource"  then spam_datasource_id(subject, reason)
      when "spam-pattern"     then reason.to_i
      when "regexp"           then REGEXP_REASONS[reason]
      when "analyst"          then ANALYST_REASONS[reason]
      when "nbayes"           then NBAYES_REASONS[reason]
      when "orion-classifier" then ORION_CLASSIFIER_REASONS[reason]
      end

      id || 0 #unclassified
    end

    def spam_datasource_id(subject, reason)
      # todo, update upstream code to add spam datasource id
      # to spammy reason so we don't have to look up a regex
      0
    end

    REGEXP_REASONS = {
      1 => "spammy neighbors",
      2 => "Fake login/email",
      3 => "Fake login/email (extended hotmail pattern)",
      4 => "Profile blog spam",
      5 => "Profile name spam",
      6 => "Suspicious profile name",
      7 => "Tech Support Wiki spam",
      8 => "blacklisted repo description",
      9 => "blacklisted repo name",
      10 => "blob content",
      11 => "body",
      12 => "compound login",
      13 => "content",
      14 => "created within 1 hour after user creation",
      15 => "created within 15s after user creation",
      17 => "description",
      18 => "excessive duplicate links to same URL",
      19 => "login (general)",
      20 => "obfuscated duplicates",
      21 => "posting",
      22 => "spammy content on wiki create",
      23 => "title",
      24 => "updated within 1 hour after user creation",
      25 => "blob content (obfuscated with tags)",
      26 => "Profile company spam",
      27 => "Profile location spam",
      28 => "login was on tainted list",
      29 => "single path name",
      30 => "filename",
      31 => "only image link soon after acct creation",
      32 => "IP was on auto-flag status",
      33 => "tech support spammer",
      34 => "spacing tricks",
    }.invert

    ANALYST_REASONS = {
      1 => "copycat",
      2 => "extra account",
      3 => "fake account",
      4 => "reported as abuse",
      5 => "munch gists",
      6 => "gist spam",
      7 => "gist comments spam",
      8 => "issue spam",
      9 => "issue comment spam",
     10 => "profile spam",
     11 => "repo spam",
     12 => "email spam",
     13 => "login",
     14 => "bot farmer",
     16 => "bitcoin miner",
     17 => "book spammer",
     18 => "flagged by staff",
     19 => "gmail gist",
     20 => "gmail account",
     21 => "malware",
     22 => "porn",
     23 => "spammy",
     24 => "star spammer",
     25 => "profile/login spam",
     26 => "student pack spammer",
     27 => "repo/issue spam",
     28 => "gist/issue comment spam",
     29 => "wiki spam",
    }.invert

    NBAYES_REASONS = {
      1 => "nbayes classified spammy",
    }.invert

    ORION_CLASSIFIER_REASONS = {
      1 => "star spammer",
    }.invert
  end
end
