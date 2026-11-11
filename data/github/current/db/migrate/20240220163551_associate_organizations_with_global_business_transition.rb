# typed: true
# frozen_string_literal: true

require "github/transitions/20240220163551_associate_organizations_with_global_business"

class AssociateOrganizationsWithGlobalBusinessTransition < ActiveRecord::Migration[7.2]
  def self.up
    return unless GitHub.enterprise?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AssociateOrganizationsWithGlobalBusiness.new(arguments)
    transition.run
  end

  def self.down
  end
end
