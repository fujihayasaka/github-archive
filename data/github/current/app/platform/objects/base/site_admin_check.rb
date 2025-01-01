# typed: true
# frozen_string_literal: true
module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      module SiteAdminCheck
        VIEWER_IS_SITE_ADMIN_KEY = "platform.viewer_is_site_admin"

        def viewer_is_site_admin?(viewer, class_name)
          has_viewer = viewer.present?

          if has_viewer.blank?
            GitHub.dogstats.increment(VIEWER_IS_SITE_ADMIN_KEY, tags: [
              "class_name:#{class_name}",
              "status:no_viewer",
            ])

            return false
          end

          is_site_admin = viewer.site_admin?

          if !is_site_admin
            GitHub.dogstats.increment(VIEWER_IS_SITE_ADMIN_KEY, tags: [
              "class_name:#{class_name}",
              "status:not_a_site_admin",
            ])

            return false
          end

          GitHub.dogstats.increment(VIEWER_IS_SITE_ADMIN_KEY, tags: [
            "class_name:#{class_name}",
            "status:success",
          ])

          true
        end

        extend self
      end
    end
  end
end
