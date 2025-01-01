# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AppOwner
    sig { params(current_user: User).returns(::Spark::RuntimeAppOwner) }
    def self.ensure_owner(current_user)
      ActiveRecord::Base.connected_to(role: :writing) do
        username = current_user.display_login

        ::Spark::RuntimeAppOwner.find_or_create_by!(owner_id: current_user.id) do |owner|
          owner.owner_id = current_user.id
          owner.permanent_name = Spark::RuntimeApp.generate_random_name
          owner.last_seen_login = username

          # TODO: This will fail for users len() > 20, but we already do on ACA deploy
          owner.deploy_login = username
        end
      end
    end
  end
end
