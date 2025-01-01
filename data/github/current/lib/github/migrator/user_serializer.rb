# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class UserSerializer < BaseSerializer
      def scope
        User.preload(:profile, :primary_user_email)
      end

      def as_json(options = {})
        {
          type: "user",
          url: url,
          avatar_url: avatar,
          login: login,
          name: name,
          bio: bio,
          company: company,
          website: website,
          location: location,
          emails: emails,
          social_accounts: social_accounts,
          billing_plan: billing_plan,
          created_at: created_at,
        }
      end

      private

      def login
        model.login
      end

      def profile
        model.profile
      end

      def avatar
        model.primary_avatar_url
      end

      def name
        profile.name if profile
      end

      def bio
        profile.bio if profile
      end

      def company
        profile.company if profile
      end

      def website
        profile.blog if profile
      end

      def social_accounts
        return [] unless profile

        profile.social_accounts.map do |account|
          {
            provider: account.key,
            url: account.url,
          }
        end
      end

      def location
        profile.location if profile
      end

      def public_email
        model.publicly_visible_email(logged_in: actor.present?) || stealth_email
      end

      def stealth_email
        StealthEmail.new(model).email
      end

      def emails
        if should_serialize_personal_data?
          model.emails.map do |email|
            {
              address: email.email,
              primary: email.primary,
              verified: email.state == "verified",
            }
          end
        else
          [{
            address: public_email,
            primary: true,
            verified: true,
          }]
        end
      end

      def billing_plan
        return unless should_serialize_personal_data? && model.plan
        {
          name: model.plan.display_name,
          space: model.plan.space / 1.kilobyte,
          private_repos: model.plan.repos,
        }
      end

      def should_serialize_personal_data?
        # The exported data is not owned by the actor
        return false if scoped_migration? && owner != model
        # The exported data cannot be administrated by the actor
        return false unless actor_can_admin?
        true
      end

      def scoped_migration?
        owner.present?
      end
    end
  end
end
