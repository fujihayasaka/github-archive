# typed: strict
# frozen_string_literal: true

class Company < ApplicationRecord::Domain::Users
  include GitHub::Validations

  MAX_NAME_LENGTH = 1024

  validates :name,
    presence: true,
    uniqueness: { case_sensitive: false },
    length: { maximum: MAX_NAME_LENGTH }

  attribute :name, StringFromBinary.new

  # Check if a given name is valid or not. Note that we allow existing company
  # names
  sig { params(name: String).returns(T::Boolean) }
  def self.valid_name?(name)
    company = Company.find_by(name: name) || Company.new(name: name)
    company.valid?
  end

  sig { returns(User::PrivateRelation) }
  def users
    user_ids = self.class.connection.select_values(Arel.sql(<<-SQL, company_id: id))
      SELECT user_id FROM `companies_users` WHERE `company_id` = :company_id
    SQL
    User.where(id: user_ids)
  end
end
