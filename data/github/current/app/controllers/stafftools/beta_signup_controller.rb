# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

module Stafftools
  class BetaSignupController < StafftoolsController

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:add, :show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:add, :show],
      optional: true

    BATCH_SIZE = 100

    BETAS = {
      "bitbucket-migrations": BitbucketServerMigrations::Beta,
      "copilot-for-enterprise": ::Copilot::CopilotForEnterpriseBeta,
      "copilot-customization": ::Copilot::CustomizationBeta,
      "copilot-chat-jetbrains": ::Copilot::ChatJetbrainsBeta,
      "copilot-extensions": ::Copilot::ExtensionsBeta,
      "copilot-next-edit-suggestions": ::Copilot::NextEditSuggestionsBeta,
      "copilot-workspaces": ::Copilot::WorkspaceBeta,
      "github-spark": GitHubSparkBeta,
      "copilot-code-review": ::Copilot::CodeReviewBeta,
    }

    before_action :beta_required, except: :index

    def index
      render "stafftools/beta_signup/index", locals: { betas: BETAS }
    end

    def show
      memberships = beta.waitlist.preload(:member, :actor, :parent).order(created_at: :asc)

      if beta.only_show_onboardable_members?
        memberships = memberships.where(can_onboard: true)
      end

      if params[:query].present?
        for_user = memberships.with_member_login(params[:query].strip)
        for_business = memberships.with_business_member_slug(params[:query].strip)
        for_parent = memberships.with_parent_login(params[:query].strip)
        memberships = for_user + for_business + for_parent
      end

      memberships = memberships.paginate(page: current_page, per_page: 100)

      render "stafftools/beta_signup/show", locals: {
        beta: beta,
        memberships: memberships,
        total_count: beta.waitlist.count,
        enabled_count: beta.waitlist.where(feature_enabled: true).count
      }
    end

    # Note that an early access member could be a User, Organization, or
    # Business.
    def toggle_access # rubocop:todo GitHub/UseRestfulActions
      membership = ::EarlyAccessMembership.find(params[:membership_id])
      member = membership.member

      if member.feature_enabled?(beta.feature_slug.to_sym) || membership.feature_enabled?
        if member.is_a?(::Business)
          offboard_business!(membership)
        else
          offboard!(member)
        end
      else
        if member.is_a?(::Business)
          onboard_business!(membership)
        else
          onboard!([member.login])
        end
      end

      head :ok
    end

    # Note that an early access member could be a User, Organization, or
    # Business. This method currently only supports Users and Organizations.
    def submit # rubocop:todo GitHub/UseRestfulActions
      submitted_membernames = params[:users].try(:split, /\s+/) || []
      added_members = T.let([], T::Array[T.untyped])

      submitted_membernames = submitted_membernames.map do |membername|
        next if membername.blank?
        membername.delete_prefix("@")
      end.compact.uniq

      ::User.where(login: submitted_membernames).in_batches(of: BATCH_SIZE) do |users|
        found_membernames = users.pluck(:login)
        onboard!(found_membernames)
        added_members += found_membernames
      end
      failed_members = submitted_membernames.map(&:downcase) - added_members.map(&:downcase)

      render "stafftools/beta_signup/add", locals: {
        beta: beta,
        added_users: added_members,
        failed_users: failed_members,
      }
    end

    def add # rubocop:todo GitHub/UseRestfulActions
      render "stafftools/beta_signup/add", locals: { beta: beta }
    end

    # Public: Bulk onboard early access members into the beta.
    #
    # Pulls a batch of users with early access memberships, sends them the welcome email
    # and enables them into the FeatureFlag
    def onboard_batch # rubocop:todo GitHub/UseRestfulActions
      unless beta.respond_to? :bulk_onboard_batch_size
        return head :ok
      end

      if beta.respond_to?(:survey_choices_scoped_to) && params[:choice].present?
        beta.onboard_job.perform_later([], batch_size: beta.bulk_onboard_batch_size, choice: params[:choice])
      else
        beta.onboard_job.perform_later([], batch_size: beta.bulk_onboard_batch_size)
      end

      head :ok
    end

    # Public: Onboard early access members into the beta.
    #
    # If they have an early access membership we'll send them a nice welcome
    # email and instrument their joining otherwise we just enable them into the FeatureFlag
    #
    # Note that an early access member could be a User, Organization, or
    # Business. This method currently only supports Users and Organizations.
    def onboard!(member_logins) # rubocop:todo GitHub/UseRestfulActions
      if beta.respond_to?(:supply_onboarding_actor?) && beta.supply_onboarding_actor?
        beta.onboard_job.perform_later(member_logins, actor: current_user)
      else
        beta.onboard_job.perform_later(member_logins)
      end
    end

    # Public: Offboard the early access member from the beta.
    #
    # If they have an early access membership we'll instrument their offboarding, otherwise
    # we'll just disable them from the FeatureFlag
    def offboard!(member) # rubocop:todo GitHub/UseRestfulActions
      # Bounce if the member is already offboarded
      return unless GitHub.flipper[beta.feature_slug].enabled?(member)

      if membership = beta.waitlist.find_by(member: member)
        membership.update!(feature_enabled: false)
        return unless member.is_a?(::User) && member.user?

        GlobalInstrumenter.instrument("user.beta_feature.unenroll",
          actor: member,
          action: "unenroll",
          feature: beta.feature_slug,
        )

        if beta.respond_to?(:offboard_job)
          beta.offboard_job&.perform_later([member.login])
        end

        disable!(member)
      else
        disable!(member)
      end
    end

    private

    def onboard_business!(membership)
      if membership.can_onboard
        beta.onboard_job.perform_later(membership)
      end
    end

    def offboard_business!(membership)
      membership.feature_enabled = false
      membership.save!
    end

    # Enable the beta's feature flag for the early access member.
    def enable!(member)
      feature.enable(member) # rubocop:disable GitHub/FeatureManagement/NoFeatureFlagManipulation
    end

    # Disable the beta's feature flag for the early access member.
    def disable!(member)
      feature.disable(member) # rubocop:disable GitHub/FeatureManagement/NoFeatureFlagManipulation
    end

    memoize def feature
      FlipperFeature.find_by!(name: beta.feature_slug)
    end

    def beta_required
      render_404 unless beta
    end

    memoize def beta
      BETAS[params[:beta].to_sym]&.new
    end
  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
