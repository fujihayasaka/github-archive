# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class Csv
      extend T::Sig

      sig do
        params(
          organization: ::Organization,
          uploaded_csv: ActionDispatch::Http::UploadedFile
        ).returns(GitHub::Result)
      end
      def self.parse(organization, uploaded_csv)
        GitHub::Result.new do
          records = process_csv(uploaded_csv)
          raise StandardError, "No valid users found" if records.empty?

          found_errors = []
          emails = []
          logins = []

          records.compact.uniq.each do |csv_user|
            next unless csv_user.present?

            if csv_user.include?("@")
              if ::User.valid_email?(csv_user)
                emails << csv_user
              else
                found_errors << csv_user
              end
            else
              logins << csv_user.downcase
            end
          end

          # get all the users by their email
          # note: this business property is just here to add the emu shortcode, and doesnt scope to "this business"
          # the keys have the emu shortcode removed
          users_by_email = ::User.find_by_emails(emails, business: organization.business)
          users_by_login = ::User.where(login: logins).to_a

          # all the users we know about from their email, emu aware
          known_users_from_emails = users_by_email.values

          # all the emails and logins that cannot be mapped to users on GitHub
          missing_user_emails = emails - users_by_email.keys
          missing_user_logins = logins - users_by_login.map(&:display_login).map(&:downcase)

          # a trap for if their exist users with both their email and login in the csv
          all_found_users = (known_users_from_emails + users_by_login).uniq(&:id)
          all_found_user_ids = T.let(all_found_users.map(&:id), T::Array[Integer])

          org_user_ids = T.let(organization.people_ids, T::Array[Integer])

          # filter on the users that belong to this org, and those that don't
          users = all_found_users.partition { |user| !org_user_ids.include?(user.id) }

          new_users_count = (missing_user_emails + all_found_user_ids - org_user_ids).count

          found_errors = (found_errors << missing_user_logins).flatten
          github_users = users[0].map { |u| { new_user: true, user: u } } + users[1].map { |u| { new_user: false, user: u } }

          {
            new_users: new_users_count,
            github_users: github_users,
            email_users: missing_user_emails,
            found_errors: found_errors,
            total_users: missing_user_emails.count + all_found_users.count
          }
        end
      end

      sig do
        params(organization: ::Organization, uploaded_csv: ActionDispatch::Http::UploadedFile)
          .returns({
            found_errors: T.nilable(T::Array[String]),
            new_users: T.nilable(Integer),
            email_users: T.nilable(T::Array[String]),
            github_users: T::Array[{ new_user: T::Boolean, user: ::User }],
            total_users: T.nilable(Integer)
          })
      end
      def self.parse_as_json(organization, uploaded_csv)
        result = Copilot::SeatManagement::Csv.parse(organization, uploaded_csv)

        return {
          found_errors: [],
          new_users: 0,
          email_users: [],
          github_users: [],
          total_users: 0
        } unless result.ok?

        hash = result.value!

        users = hash[:github_users].nil? ? [] : hash[:github_users]

        {
          found_errors: hash[:found_errors],
          new_users: hash[:new_users],
          email_users: hash[:email_users],
          github_users: users.map { |user| Copilot::SeatManagement::Csv.serialize_user(T.cast(user, { new_user: T::Boolean, user: ::User })) },
          total_users: hash[:total_users]
        }
      end

      sig do
        params(data: { new_user: T::Boolean, user: ::User })
          .returns(T::Hash[String, T.any(String, T::Boolean)])
      end
      def self.serialize_user(data)
        {
          id: data[:user].id,
          email: data[:user].remove_shortcode(data[:user].email),
          display_login: data[:user].display_login,
          profile_name: data[:user].profile_name,
          avatar: data[:user].primary_avatar_url(50),
          is_new_user: data[:new_user]
        }
      end

      sig do
        params(copilot_organization: Copilot::Organization,
               github_usernames: T::Array[::String],
               email_users: T::Array[String],
               current_user: ::User).void
      end
      def self.save(copilot_organization, github_usernames, email_users, current_user)
        if github_usernames.any?
          github_users = ::User.where(login: github_usernames).to_a
          copilot_organization.assign(github_users, current_user)
        end

        if email_users.any?
          copilot_organization.assign(email_users, current_user)
        end
      end

      sig do
        params(uploaded_csv: ActionDispatch::Http::UploadedFile)
          .returns(T::Array[String])
      end
      def self.process_csv(uploaded_csv)
        GitHub.logger.with_named_tags("code.function" => "process_csv") do
          rows = CSV.parse(uploaded_csv.read)
          rows.flat_map do |row|
            row.map { |item| item.to_s.gsub(/\r|\n|,|\ /, "").to_s.strip }
          end
        end
      rescue CSV::MalformedCSVError => e
        GitHub.logger.error("There was an error parsing CSV file", e)
        GitHub.logger.info("Trying to manually parse the CSV because YOLO")
        uploaded_csv.rewind # BE KIND, REWIND
        uploaded_csv.read.split(",").map do |row|
          row.gsub(/\r|\n/, "").to_s.strip
        end
      end
    end
  end
end
