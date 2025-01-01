# typed: strict
# frozen_string_literal: true

module Search::RepositoryQueryFilters
  extend T::Sig

  sig { params(query: T.nilable(String), type: T.nilable(String), login: String).returns(String) }
  def search_phrase(query, type, login)
    query ||= ""
    phrase = add_type_to_query(query, type)
    phrase += " user:#{login}"
  end

  sig { params(query: String, type: T.nilable(String)).returns(String) }
  def add_type_to_query(query, type)
    return query if type.blank?

    type_string = case type
    when "public"      then "is:public archived:false"
    when "private"     then "is:private"
    when "fork"        then "fork:only archived:false"
    when "mirror"      then "mirror:true archived:false"
    when "template"    then "template:true archived:false"
    when "source"      then "mirror:false archived:false fork:false"
    when "archived"    then "archived:true"
    when "sponsorable" then "is:sponsorable"
    else ""
    end

    query.present? ? "#{query} #{type_string}" : type_string
  end

  sig { params(order_by: T.untyped).returns(T.nilable([String, String])) }
  def search_sort(order_by)
    return unless order_by

    direction = (order_by[:direction] || "desc").downcase
    case order_by[:field]
    when "pushed_at"
      ["updated", direction]
    when "updated_at"
      ["updated", direction]
    when "created_at"
      ["created", direction]
    when "name"
      ["name", direction]
    else
      # can't sort by "recently starred" while searching -- see #60971
      ["stars", direction]
    end
  end
end
