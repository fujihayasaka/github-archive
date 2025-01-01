# typed: strict
# frozen_string_literal: true

module UserPropensity
  class CopilotBusiness
    class Group < T::Enum
      enums do
        High   = new
        Medium = new
        Low    = new
        None   = new(nil)
      end

      sig { returns(String) }
      def to_s
        serialize.to_s
      end
    end

    include GitHub::Memoizer

    sig { params(user: User).returns(T.nilable(T.attached_class)) }
    def self.find(user)
      return unless user.feature_enabled?(:copilot_business_propensity_nudge)

      propensity_data = Site::KV.store.get("user_propensity/copilot_business/v1/#{user.id}").value { nil }
      return if propensity_data.nil?

      propensity = JSON.parse(propensity_data)

      new(
        user: user,
        group: Group.deserialize(propensity["group"]),
        organization_id: propensity["org_id"],
        organization_login: propensity["org_login"],
        relationship_type: propensity["relationship_type"],
        org_propensity_score: propensity["org_propensity_score"]
      )
    end

    sig { params(user: User, organization_id: T.nilable(Integer), organization_login: T.nilable(String), relationship_type: T.nilable(String), org_propensity_score: T.nilable(Float), group: T.any(Group, String)).returns(T.any(FalseClass, CopilotBusiness)) }
    def self.create(user:, organization_id:, organization_login:, relationship_type:, org_propensity_score:, group: Group::None)
      new(
        user:,
        organization_id:,
        organization_login:,
        relationship_type:,
        org_propensity_score:,
        group: Group.deserialize(group)
      ).save
    end

    sig { returns(GitHub::KV) }
    def self.store
      Site::KV.store
    end

    sig { returns(T.nilable(String)) }
    attr_reader :organization_login

    sig { params(user: User, organization_id: T.nilable(Integer), organization_login: T.nilable(String), relationship_type: T.nilable(String), org_propensity_score: T.nilable(Float), group: Group).void }
    def initialize(user:, organization_id:, organization_login:, relationship_type:, org_propensity_score:, group: Group::None)
      @user = user
      @group = group
      @organization_id = organization_id
      @organization_login = organization_login
      @relationship_type = relationship_type
      @org_propensity_score = org_propensity_score
    end

    sig { params(expires: Time).returns(T.any(FalseClass, CopilotBusiness)) }
    def save(expires: 1.week.from_now)
      valid = [@user, @group, @organization_id, @organization_login, @relationship_type].all?(&:present?)
      return false unless valid

      self.class.store.set(store_key, serialize, expires:)
      self
    end

    sig { returns(T::Boolean) }
    def show_purchase_nudge?
      (high? || medium?) && show_nudge?
    end

    sig { returns(T::Boolean) }
    def show_explore_nudge?
      low? && show_nudge?
    end

    sig { returns(Group) }
    def group
      @group
    end

    private

    sig { returns(T::Boolean) }
    def show_nudge?
      admin? && !emu? && !copilot_enabled_for_organization?
    end

    sig { returns(T::Boolean) }
    def high?
      @group == Group::High
    end

    sig { returns(T::Boolean) }
    def medium?
      @group == Group::Medium
    end

    sig { returns(T::Boolean) }
    def low?
      @group == Group::Low
    end

    sig { returns(T::Boolean) }
    def admin?
      @relationship_type == "owner" && !!organization&.adminable_by?(@user)
    end

    sig { returns(T::Boolean) }
    def emu?
      !!@user.is_enterprise_managed?
    end

    sig { returns(T::Boolean) }
    def copilot_enabled_for_organization?
      !!copilot_organization&.copilot_enabled?
    end

    sig { returns(T.nilable(Copilot::Organization)) }
    memoize def copilot_organization
      return unless @organization_id.present?

      org = Organization.find(@organization_id)
      return unless org.present?

      Copilot::Organization.new(org)
    end

    sig { returns(T.nilable(Organization)) }
    def organization
      copilot_organization&.organization_object
    end

    sig { returns(String) }
    def store_key
      "user_propensity/copilot_business/v1/#{@user.id}"
    end

    sig { returns(String) }
    def serialize
      {
        "group" => @group.serialize,
        "org_id" => @organization_id,
        "org_login" => @organization_login,
        "org_propensity_score" => @org_propensity_score,
        "relationship_type" => @relationship_type
      }.to_json
    end
  end
end
