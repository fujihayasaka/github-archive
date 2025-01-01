# typed: strict
# frozen_string_literal: true

module LeadSignal
  class Base
    extend T::Sig
    extend T::Helpers
    abstract!

    sig { abstract.returns(T::Hash[Symbol, String]) }
    def attributes; end

    sig { abstract.returns(String) }
    def campaign_name; end

    include ActiveModel::Model
    include Kernel

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
      LeadIngestionSubmissionJob.perform_later(self.attributes.merge(email: email, cDLProgramName: campaign_name))
    end

    class InvalidLeadSignalError < StandardError; end
  end
end
