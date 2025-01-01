# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AdvisoryCreditOrderField < Platform::Enums::Base
      visibility :under_development

      description "Properties by which advisory credits connections can be ordered."


      value "ID", "Order credits by id", value: "id"
    end
  end
end
