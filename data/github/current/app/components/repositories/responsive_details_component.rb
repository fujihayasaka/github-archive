# typed: true
# frozen_string_literal: true

module Repositories
  class ResponsiveDetailsComponent < ApplicationComponent
    extend T::Helpers

    include UsersHelper
    include StacksHelper
    include RepositoriesHelper

    sig { params(repository: Repository).void }
    def initialize(repository:)
      @repository = repository

      coc_promise = @repository.preferred_files.async_fetch(:code_of_conduct)
      contributing_promise = @repository.preferred_files.async_fetch(:contributing)
      security_policy_promise = @repository.preferred_files.async_fetch(:security)

      @code_of_conduct, @contributing, @security_policy = Promise.all([
        coc_promise,
        contributing_promise,
        security_policy_promise
      ]).sync
    end

    sig { returns(Symbol) }
    def repo_type_icon
      return :stack if show_stack_template_labels_icons?(@repository)
      if  @repository.template?
        @repository.public? ? :"repo-template" : :lock
      else
        @repository.public? ? :globe : :lock
      end
    end

    sig { returns(String) }
    def repo_type_text
      return "Stack repository" if show_stack_template_labels_icons?(@repository)

      RepositoriesTypeHelper.type(
        visibility: @repository.visibility,
        mirror: @repository.mirror?,
        archived: @repository.archived?,
        template: @repository.template?,
      ) + " repository"
    end

    sig { returns(T::Boolean) }
    def show_code_of_conduct?
      code_of_conduct_path.present?
    end

    memoize def code_of_conduct_path
      @code_of_conduct&.permalink(use_oid: false)
    end

    sig { returns(T::Boolean) }
    def show_contributing?
      contributing_path.present?
    end

    memoize def contributing_path
      @contributing&.permalink(use_oid: false)
    end

    sig { returns(T::Boolean) }
    def show_security_policy?
      security_policy_path.present?
    end

    memoize def security_policy_path
      @security_policy&.permalink(use_oid: false)
    end
  end
end
