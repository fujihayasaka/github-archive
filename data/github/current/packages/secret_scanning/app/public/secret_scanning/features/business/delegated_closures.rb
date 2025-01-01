# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  class DelegatedClosures
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.feature_available?
      @business.advanced_security_purchased?
    end

    sig { params(actor: User).returns(T::Boolean) }
    def can_view_request_list?(actor)
      return false unless self.feature_available?
      return false unless @business.admins.include?(actor)
      true
    end
  end
end
