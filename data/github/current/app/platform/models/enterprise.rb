# typed: true
# frozen_string_literal: true

class Platform::Models::Enterprise < SimpleDelegator
  include GitHub::Relay::GlobalIdentification

  attr_reader :token, :business

  # business - A ::Business to delegate to.
  # token - A String representing a token for a ::BusinessAdministratorInvitation.
  def initialize(business, token)
    super(business)
    @token = token
    @business = business
  end

  def readable_by?(user)
    T.bind(self, T.untyped)
    return super if token.nil?
    if FeatureFlag.vexi.enabled?(:enterprise_invitation_token_validation, business, default: false)
      ::BusinessAdministratorInvitation.pending.where(hashed_token: token, business_id: business.id).exists?
    else
      ::BusinessAdministratorInvitation.pending.where(hashed_token: token).exists?
    end
  end
end
