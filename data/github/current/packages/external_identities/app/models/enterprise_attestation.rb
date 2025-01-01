# typed: false
# frozen_string_literal: true

class EnterpriseAttestation

  DEFAULT_PAGE_SIZE = 50
  VALID_PAGE_SIZE_RANGE = (1..1000)
  VALID_PAGE_RANGE = (1..2001)
  MAX_CONTRACTORS = 100_000

  class ContractorsLimitExceeded < Exception; end

  # Public: Fetch list of contractor User IDs.
  def self.contractor_ids(per_page: DEFAULT_PAGE_SIZE, page: nil)
    per_page = DEFAULT_PAGE_SIZE unless VALID_PAGE_SIZE_RANGE.include?(per_page)
    page = 1 unless VALID_PAGE_RANGE.include?(page)

    return WillPaginate::Collection.new(page, per_page, 0)  unless GitHub.restrict_contractors_from_default_access_to_internal_repos?

    ids = storage.fetch_ids
    ids.paginate(page: page, per_page: per_page)
  end

  # Public: Check if given User ID has contractor attestation set.
  def self.contractor?(user_id)
    return false unless GitHub.restrict_contractors_from_default_access_to_internal_repos?
    storage.exists?(user_id)
  end

  # Public: Get attestation for given User ID.
  def self.get(user_id)
    return unless GitHub.restrict_contractors_from_default_access_to_internal_repos?
    if storage.exists?(user_id)
      new(user_id: user_id, contractor: true)
    end
  end

  # Public: Set attestation for given User ID.
  #
  # Raises ContractorsLimitExceeded if contractor is true but we are at
  # capacity (MAX_CONTRACTORS)
  def self.set(user_id, contractor: false)
    return false unless GitHub.restrict_contractors_from_default_access_to_internal_repos?
    storage.set(user_id, contractor: contractor)
  end

  attr_reader :user_id, :contractor

  def initialize(user_id:, contractor:)
    @user_id = user_id
    @contractor = contractor
  end

  def self.storage
    @storage ||= Storage.new(ExternalIdentities::KV)
  end
  private_class_method :storage

  class Storage
    CONTRACTOR_KEY = "ent:attest:contractor:%d"
    CONTRACTORS_INDEX_KEY = "ent:attest:contractors"
    CONTRACTORS_INDEX_SPLIT_SIZE = 2000

    attr_reader :kv

    def initialize(kv)
      @kv = kv
    end

    def fetch_ids
      get_index
    end

    def exists?(user_id)
      kv.exists(key_for(user_id)).value!
    end

    def set(user_id, contractor:)
      kv.connection.transaction do
        ids = fetch_ids

        if contractor
          if ids.count >= MAX_CONTRACTORS
            raise ContractorsLimitExceeded.new("Limit of #{MAX_CONTRACTORS} reached. Cannot add attestation.")
          end
          kv.set(key_for(user_id), encode_value(Time.now.to_i))
          set_index(ids | [user_id])
        else
          set_index(ids - [user_id])
          kv.del(key_for(user_id))
        end

        true
      end
    end

    private

    def key_for(user_id)
      if user_id.is_a?(User)
        CONTRACTOR_KEY % user_id.id
      else
        CONTRACTOR_KEY % user_id
      end
    end

    def encode_value(arr)
      arr.to_json
    end

    def decode_value(val, default: nil)
      return default unless val.present?
      JSON.parse(val)
    end

    # Stores the list of IDs using the legacy key name (ent:attest:contractors),
    # unless they exceed a threshold; in this case, store the subsequent keys in
    # ent:attest:contractors:2, ent:attest:contractors:3, etc.
    def set_index(all_ids)
      key = CONTRACTORS_INDEX_KEY
      all_ids.each_slice(CONTRACTORS_INDEX_SPLIT_SIZE) do |ids|
        kv.set(key, encode_value(ids))
        key = next_index_key(key)
      end
      kv.del(key) # So we don't read leftovers from a list shrink
    end

    # Returns the list of attested IDs, combining if split among multiple keys,
    # keeping compatibility with old versions that did not split.
    #
    # See #set_index
    def get_index
      key = CONTRACTORS_INDEX_KEY
      all_ids = []
      while v = kv.get(key).value { nil }
        all_ids += decode_value(v, default: [])
        key = next_index_key(key)
      end

      all_ids
    end

    def next_index_key(key)
      suffix = key.match(/^#{CONTRACTORS_INDEX_KEY}(:\d+)?$/).captures.first || ":1"
      next_value = suffix.split(":").last.to_i + 1

      "#{CONTRACTORS_INDEX_KEY}:#{next_value}"
    end
  end

end
