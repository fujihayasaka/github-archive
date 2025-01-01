# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RuntimeAppDeploy < Platform::Objects::Base
      model_name "::Spark::RuntimeAppDeploy"
      description "An internal object for getting a Runtime app deployment bundle URL"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal, environments: [:dotcom]

      minimum_accepted_scopes ["site_admin"]

      implements_node templates: [[:rad, :id]],
        as: "RAD", allow_nil_for: [:id], ready_date: Platform::Helpers::GlobalId::COHORT_5 do |runtime_app_deploy|
          { prefix: :rad, id: runtime_app_deploy.id }
        end

      database_id_field

      field :runtime_app_id, Integer, "The ID of the runtime app this deployment belongs to.", null: false
      field :owner_id, Integer, "The ID of the user who owns the runtime app.", null: false
      def owner_id
        Promise.resolve(object.async_runtime_app).then do |runtime_app|
          T.must(runtime_app).user_id
        end
      end

      field :signed_url, Scalars::URI, "The URL to download the deployment bundle.", null: false
      def signed_url
        object.signed_url
      end
    end
  end
end
