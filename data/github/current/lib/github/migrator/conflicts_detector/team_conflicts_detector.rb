# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class ConflictsDetector
      class TeamConflictsDetector < Base

        protected

        ##
        # This method rewrites the team url based off of any mapping that may
        # have happened to the parent organization.
        #
        # For example, say we're importing
        # https://ghe.example.com/orgs/acme/teams/data-liberation
        # and the `acme` org has been mapped to the `github` org on the target.
        # We want to generate the URL
        # https://ghe.example.com/orgs/acme/teams/data-liberation to use to
        # detect conflicts properly. We do this by extracting the org login
        # (acme) from the team URL, generating an org URL for that, and seeing
        # if there is a migratable resource that matches that source url (there
        # always should be). If that migratable resource has been mapped, the
        # `#model` attribute will be set, and we can use that to get the new
        # login
        #
        alias_method :unrewritten_url, :reference_url
        def reference_url
          if parent_organization_model
            url_translator.expand(
              target_url_templates["team"],
              team_url_params.merge(
                url_translator.default_params,
              ).merge(
                "owner" => parent_organization_model.login,
              ).merge(
                "team" => normalize_team_name(team_url_params["team"]),
              ),
            )
          end
        end

        def has_invalid_url?
          url_invalid?(unrewritten_url)
        end

        private

        ##
        # Extracts org and team name from the original URL
        #
        def team_url_params
          url_translator.extract(
            source_url_templates["team"],
            migratable_resource.source_url,
          )
        end

        ##
        # Generates an org URL based off the team's URL
        #
        def parent_org_url
          url_translator.expand(
            source_url_templates["organization"],
            team_url_params.merge("organization" => team_url_params["owner"]),
          )
        end

        ##
        # Looks up parent org migratable resource and returns the model
        #
        def parent_organization_model
          url = target_url_for(parent_org_url)

          model_for_url(url)
        end

        def normalize_team_name(name)
          CGI.unescape(name).parameterize
        end
      end
    end
  end
end
