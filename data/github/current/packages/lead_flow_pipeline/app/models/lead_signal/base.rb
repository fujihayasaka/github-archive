# typed: strict
# frozen_string_literal: true

module LeadSignal
  class Base
    extend T::Helpers
    abstract!

    sig { abstract.returns(T::Hash[Symbol, String]) }
    def attributes; end

    sig { abstract.returns(String) }
    def campaign_name; end

    include ActiveModel::Model
    include Kernel
    include GitHub::Memoizer

    sig { returns(T.nilable(String)) }
    attr_accessor :email

    validates :email, presence: true, format: { with: UserEmail::MarketingDependency::EMAIL_REGEX }

    sig { params(args: T::Hash[Symbol, T.untyped]).returns(T.any(T::Boolean, T.attached_class)) }
    def self.create(args)
      new(**args).save
    end

    sig { params(args: T::Hash[Symbol, T.untyped]).returns(T.attached_class) }
    def self.create!(args)
      new(**args).save!
    end

    sig { returns(String) }
    memoize def id
      SecureRandom.uuid
    end

    sig { returns(String) }
    def digest
      digest_data = data.except(:id) # exclude id from digest to ensure same signal generates same digest regardless of when it's created
      Digest::SHA256.hexdigest(digest_data.sort.to_h.to_s)
    end

    sig { returns(T::Hash[Symbol, String]) }
    def data
      attributes.merge(id:, email:, cDLProgramName: campaign_name)
    end

    sig { returns(T.any(T::Boolean, T.self_type)) }
    def save
      save!
    rescue InvalidLeadSignalError
      false
    end

    sig { returns(T.self_type) }
    def save!
      raise InvalidLeadSignalError, "Invalid lead signal" unless valid?

      enqueue
      self
    end

    private

    sig { void }
    def enqueue
      LeadIngestionSubmissionJob.perform_later(data)
      log_enqueue
    end

    sig { void }
    def log_enqueue
      GitHub.logger.info("Lead signal enqueued", {
        "code.namespace" => self.class.name,
        "code.function" => "enqueue",
        "gh.lead_ingestion.lead_id" => id,
        "gh.lead_ingestion.digest" => digest,
      })
    end

    class InvalidLeadSignalError < StandardError; end
  end
end
