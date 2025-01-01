# typed: strict
# frozen_string_literal: true

# This class is used to track feature request that a user has requested to
# their organization admins.
#
# example:
#   #### to create a new request
#   request = MemberFeatureRequest.create(requester: user, request_entity: org, feature: MemberFeatureRequest::Feature::ProtectedBranches)
#
#   #### to check if a request already exists for the given requester, organization and feature
#   MemberFeatureRequest.already_requested?(user, org, MemberFeatureRequest::Feature::ProtectedBranches) # => true
class MemberFeatureRequest < ApplicationRecord::Domain::Users
  extend T::Sig

  enum :status, { requested: 0, fulfilled: 1, dismissed: 2 }, default: :requested

  # MemberFeatureRequest relations are set with `dependent: :delete_all` at `User` and `Organization` models.
  # This will not trigger any callbacks on the MemberFeatureRequest model. If you need to do add a destroy callback
  # change the relation to `dependent: :destroy` or `dependent: :destroy_async` and add a `before_destroy` callback
  # and also change `remove_all_member_requests` method to use `destroy` instead of `delete_all`.
  belongs_to :requester, class_name: "User", optional: false
  belongs_to :organization, optional: false
  belongs_to :request_entity, polymorphic: true, optional: true
  belongs_to :billing_entity, polymorphic: true, optional: true
  belongs_to :dismissed_by, class_name: "User", optional: true

  before_validation :dual_write_entities

  # The feature field is an enum, so it's stored as an integer in the database and this type is mapped to the
  # corresponding MemberFeatureRequest::Feature enum. You should pass a correspoding enum value to this property
  # when creating a new request.
  #   For example: MemberFeatureRequest.new(feature: MemberFeatureRequest::Feature::ProtectedBranches)
  serialize :feature, coder: Feature

  scope :protected_branches, -> { where(feature: MemberFeatureRequest::Feature::ProtectedBranches) }
  scope :custom_repository_roles, -> { where(feature: MemberFeatureRequest::Feature::CustomRepositoryRoles) }
  scope :member_requests, -> { where.not(billing_entity_type: "Business") }
  scope :admin_requests, -> { where(billing_entity_type: "Business") }

  validates :feature, uniqueness: { scope: [:requester, :request_entity, :billing_entity], message: "already requested" },
    presence: { message: "can't be blank or is invalid" }
  validate :requester_must_be_org_member_or_collaborator, on: :create
  validate :requester_able_to_request_of_entity, on: :create
  validate :copilot_seat_enabled_for_member, on: :create

  # To filter out soft deleted organizations in order not to display the requests for them
  has_many :soft_deleted_organizations, foreign_key: :organization_id, primary_key: :request_entity_id, class_name: "SoftDeletedOrganization", inverse_of: :organization
  scope :active_request_entities, -> { where.missing(:soft_deleted_organizations) }

  sig { void }
  def dual_write_entities
    self.organization = self.request_entity

    self.billing_entity ||= self.request_entity
  end

  # This method checks if a request has been fulfilled for the given requester, organization and feature.
  #
  # @param requester [User] the user who is requesting the feature
  # @param request_entity [Organization] the request_entity that the requester is requesting the feature for
  # @param feature [MemberFeatureRequest::Feature] the feature that the requester is requesting
  #
  # @return [Boolean] true if a request has been fulfilled for the given requester, request_entity and feature
  sig { params(requester: User, request_entity: Organization, feature: MemberFeatureRequest::Feature, billing_entity: T.nilable(T.any(Business, Organization))).returns(T::Boolean) }
  def self.request_fulfilled?(requester, request_entity, feature, billing_entity = nil)
    billing_entity ||= request_entity
    where(requester:, request_entity:, billing_entity:, feature:).fulfilled.exists?
  end

  sig { params(requester: User, request_entity: Organization, feature: MemberFeatureRequest::Feature, billing_entity: T.nilable(T.any(Business, Organization))).returns(T.nilable(MemberFeatureRequest)) }
  def self.find_request(requester, request_entity, feature, billing_entity = nil)
    billing_entity ||= request_entity
    where(requester:, request_entity:, billing_entity:, feature:).last
  end

  # This method checks if a request already exists for the given requester, request_entity (Organization) and feature.
  #
  # @param requester [User] the user who is requesting the feature
  # @param request_entity [Organization] the organization that the requester is requesting the feature for
  # @param feature [MemberFeatureRequest::Feature] the feature that the requester is requesting
  # @param billing_entity the entity that will be billed for the feature
  #
  # @return [Boolean] true if a request already exists for the given requester, request_entity (Organization) and feature
  sig { params(requester: User, request_entity: Organization, feature: MemberFeatureRequest::Feature, billing_entity: T.nilable(T.any(Business, Organization))).returns(T::Boolean) }
  def self.already_requested?(requester, request_entity, feature, billing_entity = nil)
    billing_entity ||= request_entity
    where(requester:, request_entity:, billing_entity:, feature:).requested.exists?
  end

  # This method checks if a request can be made for the given requester, request_entity (Organization) and feature.
  #
  # @param requester [User] the user who is requesting the feature
  # @param request_entity [Organization] the organization or Business that the requester is requesting the feature for
  # @param feature [MemberFeatureRequest::Feature] the feature that the requester is requesting
  #
  # @return [Boolean] true if a request can be made for the given requester, request_entity (Organization) and feature
  sig { params(requester: User, request_entity: Organization, feature: MemberFeatureRequest::Feature).returns(T::Boolean) }
  def self.can_request?(requester, request_entity, feature)
    !request_entity.adminable_by?(requester) && !feature.supported?(request_entity: request_entity)
  end

  # This method cancels a request that is in progress if it exists.
  #
  # @param requester [User] the user who requested the feature
  # @param request_entity [Organization] the request_entity that the requester requested the feature for
  # @param feature [MemberFeatureRequest::Feature] the feature that the requester requested
  #
  # @return [MemberFeatureRequest, false] the canceled request or false if request couldn't be destroyed
  #
  # @raise [ActiveRecord::RecordNotFound] raised when no request exists for the given requester, request_entity and feature
  sig { params(requester: User, request_entity: Organization, feature: MemberFeatureRequest::Feature, billing_entity: T.nilable(T.any(Business, Organization))).returns(T.any(MemberFeatureRequest, FalseClass)) }
  def self.cancel_request!(requester, request_entity, feature, billing_entity = nil)
    billing_entity ||= request_entity
    request = find_by!(requester:, request_entity:, billing_entity:, feature:)

    request.destroy!.tap do
      GlobalInstrumenter.instrument("member_feature_request.cancel", {
        actor: requester,
        member_feature_request: request,
        cancelled_at: Time.zone.now
      })
    end
  end

  # Removes all requests for a membership (a requester belonging to an request_entity)
  #
  # @param requester [User] the user who requested the feature
  # @param request_entity [Organization] the request_entity that the requester requested the features
  #
  # @return [void]
  sig { params(requester: User, request_entity: Organization).void }
  def self.remove_all_member_requests(requester, request_entity)
    requests = where(requester:, request_entity:)
    with_write { requests.delete_all }
  end

  # This method returns all pending requests for a given request_entity.
  # This excludes any features that are already included in the request_entity's plan and individual requirements satisfied.
  # This method does not include dismissed requests.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  #
  # @return [ActiveRecord::Relation] the requests for the given request_entity excluding any features that are already included in the request_entity's plan
  sig { params(request_entity: Organization).returns(ActiveRecord::Relation) }
  def self.requested_member_requests(request_entity)
    features = Feature.not_included_in_org(request_entity)
    # For CopilotForBusiness, request is not satisfied until the requester gets a seat (aka status == fulfilled)
    features << MemberFeatureRequest::Feature::CopilotForBusiness

    where(request_entity:).member_requests.where(feature: features).requested
  end

  # Returns the total number of requests for a given feature.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  # @param feature [MemberFeatureRequest::Feature] the feature to check for requests
  #
  # @return [Integer] the total number of requests for the given feature
  sig { params(request_entity: Organization, feature: MemberFeatureRequest::Feature).returns(Integer) }
  def self.total_for_feature(request_entity, feature)
    requested_member_requests(request_entity).where(feature: feature).count
  end

  # Returns the total number of requests for each feature.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  #
  # @return [Hash{MemberFeatureRequest::Feature => Integer} the total number of requests for each feature
  # @example
  #  MemberFeatureRequest.total_by_feature(request_entity) # => { MemberFeatureRequest::Feature::ProtectedBranches => 1, MemberFeatureRequest::Feature::CustomRepositoryRoles => 2 }
  sig { params(request_entity: Organization).returns(T::Hash[MemberFeatureRequest::Feature, Integer]) }
  def self.total_by_feature(request_entity)
    requested_member_requests(request_entity)
      .group(:feature).count
  end

  # Returns the total number of requests for each feature created after a specific date
  #
  # @param billing_entity [Organization, Business] the billing_entity to check for member feature requests
  #
  # @return [Hash{MemberFeatureRequest::Feature => Integer} the total number of requests for each feature
  # @example
  #  MemberFeatureRequest.total_by_feature_since(billing_entity, 7.days.ago) # => { MemberFeatureRequest::Feature::ProtectedBranches => 1 }
  sig { params(billing_entity: T.any(Organization, Business), date: T.nilable(Time)).returns(T::Hash[MemberFeatureRequest::Feature, Integer]) }
  def self.total_requested_by_feature_since(billing_entity, date = nil)
    total_requested_features = self.requested.where(billing_entity: billing_entity)
    total_requested_features = total_requested_features.where("updated_at > ?", date) if date
    total_requested_features.group(:feature).count
  end

  # Returns organizations sorted by the number of feature requests.
  #
  # If any org of the business has feature requests, we need to sort the orgs by the number of feature requests
  # the priority is the admin requests and then the member requests
  sig { params(organizations: ActiveRecord::Relation, admin_feature_requests: ActiveRecord::Relation, member_feature_requests: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
  def self.sorted_organizations_by_features(organizations:, admin_feature_requests:, member_feature_requests:)
    return organizations unless admin_feature_requests.any? || member_feature_requests.any?

    grouped_admin_requests = admin_feature_requests.group(:request_entity_id).count
    grouped_member_requests = member_feature_requests.group(:request_entity_id).count

    sorted_organization_ids = organizations.pluck(:id).sort_by do |org_id|
      [-grouped_admin_requests[org_id].to_i, -grouped_member_requests[org_id].to_i]
    end

    Organization.in_order_of(:id, sorted_organization_ids)
  end

  sig { params(admin_feature_requests: ActiveRecord::Relation, member_feature_requests: ActiveRecord::Relation).returns(T::Hash[Symbol, T.untyped]) }
  def self.feature_requests_count_by_organizations(admin_feature_requests:, member_feature_requests:)
    unique_admin_requests_count = admin_feature_requests.map(&:request_entity_id).uniq.count
    unique_member_requests_count = member_feature_requests.map(&:request_entity_id).uniq.count

    {
      requests_count: unique_admin_requests_count + unique_member_requests_count,
      organizations: feature_requests_grouped_by_organization(admin_feature_requests:, member_feature_requests:)
    }
  end

  sig { params(admin_feature_requests: ActiveRecord::Relation, member_feature_requests: ActiveRecord::Relation).returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]]) }
  private_class_method def self.feature_requests_grouped_by_organization(admin_feature_requests:, member_feature_requests:)
    feature_requests = Hash.new do |h, org_id|
      h[org_id] = {
        admins: 0,
        members: 0,
        requesters: []
      }
    end

    (admin_feature_requests + member_feature_requests).each do |request|
      organization = request.request_entity
      org_data = feature_requests[organization.id]

      org_data[:requesters] << request.requester

      if organization.adminable_by?(request.requester)
        org_data[:admins] += 1
      else
        org_data[:members] += 1
      end
    end

    feature_requests
  end

  # This method returns the latest member feature request created for the given request_entity.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  #
  # @return [MemberFeatureRequest, nil] the latest request or nil if it any request found
  sig { params(request_entity: Organization).returns(T.nilable(MemberFeatureRequest)) }
  def self.latest_member_feature_request(request_entity)
    requested_member_requests(request_entity).order(updated_at: :desc).first
  end

  # This method returns the latest member feature request for a specific feature created for the given request_entity.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  # @param feature [MemberFeatureRequest::Feature] the feature to check for requests
  # @param amount [Integer] the number of usernames to return
  #
  # @return an array of usernames who requested the feature
  sig { params(request_entity: Organization, feature: MemberFeatureRequest::Feature, amount: Integer).returns(T::Array[String]) }
  def self.latest_members_by_feature_request(request_entity, feature, amount)
    requests = requested_member_requests(request_entity)
                .where(feature: feature)
                .order(updated_at: :desc)
                .first(amount)

    usernames = []
    requests.each do |request|
      usernames << request.requester.name
    end
    usernames
  end

  # Returns the total of unique members who requested for features.
  #
  # @param request_entity [Organization] the request_entity to check for member feature requests
  #
  # @return [Integer] the total of unique members who requested for features.
  # @example
  #  MemberFeatureRequest.total_members_requesting_features(request_entity) # => 3
  sig { params(request_entity: Organization).returns(Integer) }
  def self.total_members_requesting_features(request_entity)
    requested_member_requests(request_entity)
      .distinct.count(:requester_id)
  end

  # Unique identifier for member feature request notification email messages.
  # @return [String] unifier message.
  # @example
  #  member_feature_request.message_id(org, feature) => "<orgname/feature_requests/copilot_for_business@github-host>"
  sig { returns(String) }
  def message_id
    "<#{request_entity&.name}/feature_requests/#{feature}@#{GitHub.urls.host_name}>"
  end

  sig { params(actor: User).void }
  def dismiss_request!(actor:)
    update!(dismissed_by_id: actor.id, dismissed_at: Time.current, status: :dismissed)
  end

  sig { params(actor: User).returns(T::Boolean) }
  def send_dismissal_email(actor:)
    return false unless dismissed?

    event_params = {
      actor: actor,
      category: "member_feature_request",
      action: "send_dismissed_email",
      label: "request_id:#{self.id};actor_id:#{actor.id};requester_id:#{requester&.id};owner_id:#{request_entity&.id};owner_type:#{request_entity.class.to_s.downcase}",
    }
    GlobalInstrumenter.instrument("analytics.event", event_params)

    !!MemberFeatureRequestMailer.notify_dismissal(self).deliver_later
  end

  private

  sig { void }
  def requester_able_to_request_of_entity
    org = organization

    return if !org.present? || !requester.present?

    errors.add(:requester, "must be admin of the organization if the request is for the enterprise") if !org.role_of(requester).admin? && billing_entity_type == "Business"
    errors.add(:requester, "must not be admin of the organization if the request is not for the enterprise") if org.role_of(requester).admin? && billing_entity_type != "Business"
  end

  sig { void }
  def requester_must_be_org_member_or_collaborator
    org = organization
    return if !org.present? || !requester.present?

    errors.add(:requester, "must be member of the organization or an outside collaborator") if !org.direct_or_team_member?(requester) && !org.user_is_outside_collaborator?(requester&.id)
  end

  sig { void }
  def copilot_seat_enabled_for_member
    return unless MemberFeatureRequest::Feature::CopilotForBusiness == feature
    return if billing_entity.is_a?(Business)

    org = organization
    return if !org.present? || !requester.present?
    copilot_org = Copilot::Organization.new(org)

    errors.add(:requester, "already has a seat") if copilot_org.has_seat_for?(T.must(requester)) || (copilot_org.has_configuration? && copilot_org.seat_management_enabled_for_all?)
  end
end
