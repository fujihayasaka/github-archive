# typed: false
# frozen_string_literal: true

module GitHub
  class Migrator
    class UserImporter < GitHub::Migrator::Importer

      def import(attributes, options = {})
        user = User.new do |user|
          user.login = last_part_of_url(options[:target_url]) || attributes["login"]
          user.password = SecureRandom.hex
          user.hash_password
          user.created_at = attributes["created_at"]

          if primary_email = attributes["emails"].find { |email| !!email["primary"] }
            user.email = primary_email["address"]
          else
            user.email = "#{user.login}@migrations.noreply.#{GitHub.host_name}"
          end

          user.build_profile({
            name: attributes["name"],
            company: attributes["company"],
            blog: attributes["website"],
            location: attributes["location"],
          })
        end

        unless User.private_method_defined?(:skip_seat_limit_enforcement?)
          def user.enforce_seat_limit; end
        end

        user.save!
        user.emails.first.verify! if GitHub.email_verification_enabled?

        user
      rescue ActiveRecord::RecordInvalid => error
        if error.message =~ /Emails is invalid/
          user.emails = []
          user.email = "#{user.login}-#{SecureRandom.alphanumeric(6).downcase}@migrations.noreply.#{GitHub.host_name}"
          user.save!

          GitHub.logger.error("Updated user email",
            {
              :exception => error,
              "code.namespace" => "GitHub::Migrator::UserImporter#import",
              "gh.migration_tools.migration.type" => "repo",
              "gh.migration_tools.migration.model.name" => "user",
              "gh.migration_tools.migration.model.source_url" => attributes["url"],
              "gh.migration_tools.migration.model.resolution" => "updated",
              "gh.migration_tools.migration.guid" => migration_guid
            }
          )

          user
        else
          raise error
        end
      end
    end
  end
end
