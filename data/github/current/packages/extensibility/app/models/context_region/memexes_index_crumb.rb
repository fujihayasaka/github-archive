# typed: true
# frozen_string_literal: true

module ContextRegion
  class MemexesIndexCrumb < Crumb
    def label
      "Projects"
    end

    def parent
      UserCrumb.new(object)
    end

    def path_name
      case object
      when Organization
        :org_projects_beta_path
      when User
        :user_projects_path
      end
    end

    def path_args
      [object]
    end
  end
end
