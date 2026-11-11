# typed: strict
# frozen_string_literal: true

module Repos
  module BranchProtections
    module Concerns
      module ReactPayload
        extend ActiveSupport::Concern
        extend T::Helpers

        include ApplicationController::ReactDependency

        class LayoutRoutePayload < ::ReactPayload::Base
          sig { override.returns(String) }
          def route_id
            "layoutRoute"
          end

          sig { params(is_stafftools: T::Boolean).void }
          def initialize(is_stafftools: false)
            @is_stafftools = is_stafftools
          end

          sig { override.returns(T::Hash[String, T.untyped]) }
          def payload
            {
              isStafftools: @is_stafftools,
            }
          end
        end

        class IndexRoutePayload < ::ReactPayload::Base
          sig { override.returns(String) }
          def route_id
            "indexRoute"
          end

          sig { params(protected_branches: T::Array[::ProtectedBranch]).void }
          def initialize(protected_branches:)
            @protected_branches = protected_branches
          end

          sig { override.returns(T::Hash[String, T.untyped]) }
          def payload
            {
              protectedBranches: @protected_branches.map do |protected_branch|
                Repos::BranchProtections::Concerns::Structs::ProtectedBranch.serialize(protected_branch)
              end
            }
          end
        end

        class ShowRoutePayload < ::ReactPayload::Base
          sig { override.returns(String) }
          def route_id
            "showRoute"
          end

          sig { params(protected_branch: ::ProtectedBranch).void }
          def initialize(protected_branch:)
            @protected_branch = protected_branch
          end

          sig { override.returns(T::Hash[String, T.untyped]) }
          def payload
            {
              protectedBranch: Repos::BranchProtections::Concerns::Structs::ProtectedBranch.serialize(@protected_branch)
            }
          end
        end
      end
    end
  end
end
