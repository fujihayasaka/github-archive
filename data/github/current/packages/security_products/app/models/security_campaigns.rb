# typed: strict
# frozen_string_literal: true

# Helper methods on the SecurityCampaigns module
module SecurityCampaigns
  extend T::Sig

  MAX_CAMPAIGNS_COUNT = T.let(10, Integer)
  MAX_CAMPAIGNS_ERROR_MESSAGE = T.let("This organization has reached the limit of active campaigns. To create a new campaign, first delete an existing one.".freeze, String)
  CAMPAIGNS_CONCURRENT_CREATION_MESSAGE = T.let("Another campaign is being created. Please try again later.".freeze, String)
  MAX_ALERTS_COUNT = 1000
  MAX_ALERTS_REPOSITORY_COUNT = 100
  TURBOSCAN_MAX_PAGE_SIZE = 100
  REPOSITORY_VISIBILITIES = T.let(%w[internal private].freeze, T::Array[String])
  # The repository visibilities to filter for when retrieving alerts
  TURBOSCAN_REPOSITORY_VISIBILITIES = T.let([::Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_INTERNAL, ::Turboscan::Proto::RepositoryVisibility::REPOSITORY_VISIBILITY_PRIVATE], T::Array[Integer])
  TURBOSCAN_REPOSITORY_VISIBILITIES_SYMBOLS = T.let(TURBOSCAN_REPOSITORY_VISIBILITIES.map { |visibility| T.must(::Turboscan::Proto::RepositoryVisibility.lookup(visibility)) }, T::Array[Symbol])

  ONBOARDING_DISMISSAL_NOTICE_NAME = :security_campaigns_onboarding
  ONBOARDING_DISMISSAL_NOTICE_PATH = T.let("/settings/dismiss-notice/#{ONBOARDING_DISMISSAL_NOTICE_NAME}", String)

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.enabled?(entity)
    entity.is_a?(Organization) && entity.feature_enabled?(:security_campaigns)
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.creation_enabled?(entity)
    SecurityCampaigns.enabled?(entity) && entity.feature_enabled?(:security_campaigns_creation)
  end

  sig { params(entity: T.any(User, Organization)).returns(T::Boolean) }
  def self.autofix_generation_enabled?(entity)
    SecurityCampaigns.enabled?(entity) && entity.feature_enabled?(:security_campaigns_autofix_generation)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def self.show_onboarding_message?(current_user)
    !current_user.dismissed_notice?(ONBOARDING_DISMISSAL_NOTICE_NAME)
  end

end
