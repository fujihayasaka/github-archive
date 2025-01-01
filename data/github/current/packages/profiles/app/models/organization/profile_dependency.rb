# typed: true
# frozen_string_literal: true

module Organization::ProfileDependency
  def create_org_profile_readme(type:)
    if type == "member"
      return Organization::ProfileReadme::Member.new(self)
    end

    Organization::ProfileReadme::Public.new(self)
  end
end
