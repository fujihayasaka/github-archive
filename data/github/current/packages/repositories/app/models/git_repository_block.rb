# typed: true
# frozen_string_literal: true

# This class handles Repository and Gist country blocking and is used by
# GitRepositoryAccess.
#
# See GitRepositoryAccess for more information.
class GitRepositoryBlock
  CHINESE_INTERNET_BLOCKLIST = "chinese_internet_blacklist"
  HONG_KONG_INTERNET_BLOCKLIST = "hong_kong_internet_blacklist"
  RUSSIAN_INTERNET_BLOCKLIST = "russian_internet_blacklist"
  SOUTH_KOREA_INTERNET_BLOCKLIST = "south_korea_internet_blacklist"
  SPANISH_INTERNET_BLOCKLIST = "spanish_internet_blacklist"
  TURKISH_INTERNET_BLOCKLIST = "turkish_internet_blacklist"
  US_TRADE_RESTRICTIONS = "us_trade_restrictions"

  COUNTRY_BLOCK_TTL = 10.minutes

  UNBLOCKED_REPO = {}.freeze

  COUNTRY_BLOCK_TYPES = {
    CHINESE_INTERNET_BLOCKLIST   => ["CN"],
    HONG_KONG_INTERNET_BLOCKLIST => ["HK"],
    RUSSIAN_INTERNET_BLOCKLIST   => ["RU"],
    SOUTH_KOREA_INTERNET_BLOCKLIST => ["KR"],
    SPANISH_INTERNET_BLOCKLIST   => ["ES"],
    TURKISH_INTERNET_BLOCKLIST   => ["TR"],
    US_TRADE_RESTRICTIONS        => %w[CU IR KP SD SY],
  }

  COUNTRY_BLOCK_DESCRIPTIONS = {
    CHINESE_INTERNET_BLOCKLIST   => "Chinese Internet Blocklist",
    HONG_KONG_INTERNET_BLOCKLIST => "Hong Kong Internet Blocklist",
    RUSSIAN_INTERNET_BLOCKLIST   => "Russian Internet Blocklist",
    SOUTH_KOREA_INTERNET_BLOCKLIST => "South Korea Internet Blocklist",
    SPANISH_INTERNET_BLOCKLIST   => "Spanish Internet Blocklist",
    TURKISH_INTERNET_BLOCKLIST   => "Turkish Internet Blocklist",
    US_TRADE_RESTRICTIONS        => "U.S. Trade Restrictions",
  }

  COUNTRY_DESCRIPTIONS = {
    "CN" => "China",
    "HK" => "Hong Kong",
    "CU" => "Cuba",
    "ES" => "Spain",
    "IR" => "Iran",
    "KP" => "North Korea",
    "KR" => "South Korea",
    "SD" => "Sudan",
    "SY" => "Syria",
    "RU" => "Russia",
    "TR" => "Türkiye",
  }

  def initialize(git_repository, type)
    @git_repository = git_repository
    @type = type
  end

  # Check if country block is enabled
  # block - the named country block to check
  def country_block_setup?(block)
    country_blocks.has_key?(block)
  end

  def blocked_countries
    country_blocks.map do |block, _url|
      COUNTRY_BLOCK_TYPES[block]
    end.flatten.join(" ")
  end

  def country_block?(country)
    country_blocks.keys.find do |block|
      COUNTRY_BLOCK_TYPES[block].include?(country)
    end
  end

  def country_block_url(country)
    country_blocks.each do |block, url|
      if COUNTRY_BLOCK_TYPES[block].include?(country)
        return url
      end
    end
    nil
  end

  # Disable access based on countries.
  #
  # user - staff user record
  # block - the block that needs to be applied
  # url - URL of the public block notice, current placed on github/nation-state-blocks
  # reason - the reason for applying the country block
  def country_block(user, block, url, reason, tos_reason: nil, content_formats: nil, source: nil)
    unless COUNTRY_BLOCK_DESCRIPTIONS.has_key?(block)
      @git_repository.errors.add(:base, "invalid country block")
      return false
    end

    if country_block_setup?(block)
      @git_repository.errors.add(:base, "block already exists for #{COUNTRY_BLOCK_DESCRIPTIONS[block]}")
      return false
    end

    if @git_repository.private?
      @git_repository.errors.add(:base, "can not country block a private #{git_repo_full_name}")
      return false
    end

    begin
      DisabledAccessReason.new do |reason|
        reason.flagged_item_id = @git_repository.id
        reason.flagged_item_type = @type
        reason.country_block = block
        reason.country_block_url = url
        reason.disabled_at = Time.current
        reason.disabled_by = user
      end.save!
    rescue ActiveRecord::RecordInvalid => e
      Failbot.report GitRepositoryAccess::Error.new(e.message)
      return false
    end

    self.class.expire_country_block_cache

    if @git_repository.is_a?(Repository)
      RepositoryMailer.country_block_notice(@git_repository, block, url).deliver_later
    end

    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(user)

    GitHub.instrument "staff.country_block", auditing_actor.merge(
      git_repo_stat_key => @git_repository,
      :user => @git_repository.owner,
      :block => block,
      :reason => reason)

    # Don't publish events for gists - they need their own stream
    if @git_repository.is_a?(Repository)
      GlobalInstrumenter.instrument "repository.country_blocked", {
        repository: @git_repository,
        actor: user,
        blocked_at: Time.now,
        type: block,
        country_codes: COUNTRY_BLOCK_TYPES[block],
        country_names: COUNTRY_BLOCK_TYPES[block].map { |cc| COUNTRY_DESCRIPTIONS[cc] },
        details: reason,
        public_block_notice_url: url,
        tos_reason: tos_reason,
        content_formats: content_formats,
        source: source
      }
    end

    true
  end

  # Removes a country block
  def remove_country_block(user, block)
    records = DisabledAccessReason.where(country_block: block,
      flagged_item_id: @git_repository.id, flagged_item_type: @type)
    records.destroy_all

    self.class.expire_country_block_cache

    auditing_actor = GitHub.guarded_audit_log_staff_actor_entry(user)

    GitHub.instrument "staff.country_unblock", auditing_actor.merge(
      git_repo_stat_key => @git_repository,
      :user => @git_repository.owner,
      :block => block)


    # Don't publish events for gists - they need their own stream
    if @git_repository.is_a?(Repository)
      GlobalInstrumenter.instrument "repository.country_unblocked", {
        repository: @git_repository,
        actor: user,
        unblocked_at: Time.now,
        type: block,
        country_codes: COUNTRY_BLOCK_TYPES[block],
        country_names: COUNTRY_BLOCK_TYPES[block].map { |cc| COUNTRY_DESCRIPTIONS[cc] },
      }
    end

    true
  end

  def country_blocks
    key = self.class.country_block_key(@type, @git_repository.id)
    self.class.all_country_blocks[key] || UNBLOCKED_REPO
  end

  def self.expire_country_block_cache
    remove_instance_variable(:@all_country_blocks_expires_at) if defined?(@all_country_blocks_expires_at)
    remove_instance_variable(:@all_country_blocks) if defined?(@all_country_blocks)
  end

  def self.all_country_blocks
    if defined?(@all_country_blocks_expires_at) && Time.now.utc < @all_country_blocks_expires_at
      return @all_country_blocks
    end

    @all_country_blocks = DisabledAccessReason.where("country_block IS NOT NULL").each_with_object({}) do |record, memo|
      key = country_block_key(record.flagged_item_type, record.flagged_item_id)
      memo[key] ||= {}
      memo[key][record.country_block] = record.country_block_url
    end

    @all_country_blocks_expires_at = Time.now.utc + COUNTRY_BLOCK_TTL
    @all_country_blocks
  end

  def self.country_block_key(type, id)
    "#{type}_#{id}"
  end

  private

  # Returns the first four of the git repository's class
  # as a symbol.  For example:
  # Repository -> :repo
  # Gist -> :gist
  def git_repo_stat_key
    git_repo_full_name.first(4).to_sym
  end

  # Returns the git repository's class as a lower
  # case string.
  def git_repo_full_name
    @git_repository.class.name.downcase
  end
end
