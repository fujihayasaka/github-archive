# typed: true
# frozen_string_literal: true

class MemexProjectWorkflowAction::ItemsFilter

  POSITIVE_INTEGERS = /[1-9][0-9]*/
  UNIT = /day/
  ALLOWED_UPDATED_UNITS = /d|w|m/
  VALID_LAST_UPDATED = /(#{POSITIVE_INTEGERS})(#{UNIT})/i
  VALID_UPDATED = /<@today-(#{POSITIVE_INTEGERS})(#{ALLOWED_UPDATED_UNITS})/i

  ASSIGNEE_QUALIFIER = /assignee:|no:assignee|has:assignee/i
  LABEL_QUALIFIER = /label:|no:label|has:label/i
  MILESTONE_QUALIFIER = /milestone:|no:milestone|has:milestone/i
  ISSUE_TYPE_QUALIFIER = /type:|no:type|has:type/i

  def self.filter_items(items, query, **opts)
    new.filter_items(items, query, **opts)
  end

  def self.filter_items_by_field(items, field_id, field_value)
    new.filter_items_by_field(items, field_id, field_value)
  end

  def self.validate_tokens(tokens)
    new.validate_tokens(tokens)
  end

  private def grammar
    return @grammar if defined?(@grammar)

    # The item can be either a `MemexItem` or `content` of a `MemexItem` (PR, Issue, Draft Issue)
    @grammar = {}
    @grammar[:positive] = {
      _: {
        _: {
          parse: -> (value) { value.to_s.downcase },
          filter: -> (parsed_value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:title) ? target.title&.downcase&.include?(parsed_value) : false
          }
        }
      },
      is: {
        open: ->(content_item) {
          return content_item.open?
        },
        draft: ->(content_item) {
          (content_item.class.method_defined? :draft?) && content_item.draft?
        },
        closed: ->(content_item) {
          return !content_item.open?
        },
        issue: ->(content_item) { !content_item.pull_request? },
        merged: ->(content_item) { content_item.pull_request? && content_item.merged? },
        pr: ->(content_item) { content_item.pull_request? },
      },
      reason: {
        completed: ->(item) { item.class.method_defined?(:state_reason) ? item.closed? && item.state_reason.nil? : false },
        reopened: ->(item) { item.class.method_defined?(:state_reason_reopened?) ? item.state_reason_reopened? : false },
        "not planned": ->(item) { item.class.method_defined?(:state_reason_not_planned?) ? !item.pull_request? && item.state_reason_not_planned? : false },
      },
      "last-updated": {
        _: {
          validate: ->(values) { values.select { |value| value.match?(/#{VALID_LAST_UPDATED}/i) } },
          parse: ->(value) {
            range, unit = value.match(/#{VALID_LAST_UPDATED}/).captures
            { range: range.to_i, unit: unit }
          },
          filter: ->(parsed_value, item) {
            is_project_item = is_project_item?(item)

            if parsed_value[:unit] == "day"
              last_updated_day = Time.now.utc - parsed_value[:range].days
            else
              return false
            end

            if is_project_item
              (item.updated_at&.utc < last_updated_day) && (item.content&.updated_at&.utc < last_updated_day)
            else
              item.updated_at&.utc < last_updated_day
            end
          }
        }
      },
      label: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.downcase },
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:labels) ? target.labels.any? { |label| label.lowercase_name == value } : false
          }
        }
      },
      assignee: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.strip.delete_prefix("@") },
          filter: ->(value, item) {
            user = user_by_login(value)
            return false unless user
            target = normalized_target(item)
            target.class.method_defined?(:assigned_to?) ? target.assigned_to?(user) : false
          }
        }
      },
      milestone: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.downcase },
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:milestone) ? target.milestone&.title&.downcase == value : false
          }
        }
      },
      type: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.downcase },
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:issue_type) ? target.issue_type&.name&.downcase == value : false
          }
        }
      },
      no: {
        label: -> (item) {
          item.class.method_defined?(:labels) ? item.labels.empty? : true
        },
        assignee: -> (item) {
          item.class.method_defined?(:assignees) ? item.assignees.empty? : true
        },
        reason: -> (item) {
          item.class.method_defined?(:state_reason) ? item.state_reason.nil? : true
        },
        milestone: -> (item) {
          item.class.method_defined?(:milestone) ? item.milestone.nil? : true
        },
        type: -> (item) {
          item.class.method_defined?(:issue_type) ? item.issue_type.nil? : true
        }
      },
      has: {
        label: -> (item) {
          item.class.method_defined?(:labels) ? item.labels.any? : false
        },
        assignee: -> (item) {
          item.class.method_defined?(:assignees) ? item.assignees.any? : false
        },
        reason: -> (item) {
          item.class.method_defined?(:state_reason) ? item.state_reason.present? : false
        },
        milestone: -> (item) {
          item.class.method_defined?(:milestone) ? item.milestone.present? : false
        },
        type: -> (item) {
          item.class.method_defined?(:issue_type) ? item.issue_type.present? : false
        }
      },
      updated: {
        _: {
          validate: ->(values) { values.select { |value| value.match?(/#{VALID_UPDATED}/i) } },
          parse: ->(value) {
            range, unit = value.match(/#{VALID_UPDATED}/).captures
            { range: range.to_i, unit: unit.to_s }
          },
          filter: ->(parsed_value, item) {
            last_updated_day = get_offset_date(**parsed_value)

            return false unless last_updated_day.present?

            return is_item_stale?(item, last_updated_day)
          }
        }
      }
    }

    @grammar[:negative] = {
      _: {
        _: {
          parse: -> (value) { value.to_s.downcase },
          filter: -> (parsed_value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:title) ? !target.title&.downcase&.include?(parsed_value) : true
          }
        }
      },
      is: {
        open: ->(content_item) {
          return false if content_item.open?
          return false if (content_item.class.method_defined? :draft?) && content_item.draft?
          return true
        },
        draft: ->(content_item) {
          return true if !content_item.class.method_defined? :draft?
          return false if content_item.draft?
          return true
        },
        closed: ->(content_item) { content_item.open? },
        issue: ->(content_item) { content_item.pull_request? },
        merged: ->(content_item) { !content_item.pull_request? || !content_item.merged? },
        pr: ->(content_item) { !content_item.pull_request? },
      },
      reason: {
        completed: ->(content_item) { content_item.class.method_defined?(:state_reason) ? !content_item.state_reason.nil? : true },
        reopened: ->(content_item) { content_item.class.method_defined?(:state_reason_reopened?) ? !content_item.state_reason_reopened? : true },
        "not planned": ->(item) { item.class.method_defined?(:state_reason_not_planned?) ? !item.pull_request? && !item.state_reason_not_planned? : true },
      },
      "last-updated": {
        _: {
          validate: @grammar[:positive][:"last-updated"][:_][:validate],
          parse: @grammar[:positive][:"last-updated"][:_][:parse],
          filter: ->(parsed_value, item) {
            if parsed_value[:unit] == "day"
              last_updated_day = Time.now.utc - parsed_value[:range].days
            else
              return false
            end

            # Project item is not stale if it was last updated either in- or outside of the project after the last_updated day
            if is_project_item?(item)
              item.updated_at&.utc >= last_updated_day || (item.content&.updated_at&.utc >= last_updated_day)
            else
              item.updated_at&.utc >= last_updated_day
            end
          }
        }
      },
      label: {
        _: {
          validate: @grammar[:positive][:"label"][:_][:validate],
          parse: @grammar[:positive][:"label"][:_][:parse],
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:labels) ? !target.labels.any? { |label| label.lowercase_name == value } : true
          }
        }
      },
      assignee: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.strip.delete_prefix("@") },
          filter: ->(value, item) {
            user = user_by_login(value)
            return true unless user
            target = normalized_target(item)
            target.class.method_defined?(:assigned_to?) ? !target.assigned_to?(user) : true
          }
        }
      },
      milestone: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.downcase },
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:milestone) ? target.milestone&.title&.downcase != value : true
          }
        }
      },
      type: {
        _: {
          validate: ->(values) { values.select(&:present?) },
          parse: -> (value) { value.to_s.downcase },
          filter: ->(value, item) {
            target = normalized_target(item)
            target.class.method_defined?(:issue_type) ? target.issue_type&.name&.downcase != value : true
          }
        }
      },
      updated: {
        _: {
          validate: ->(values) { values.select { |value| value.match?(/#{VALID_UPDATED}/i) } },
          parse: ->(value) {
            range, unit = value.match(/#{VALID_UPDATED}/).captures
            { range: range.to_i, unit: unit.to_s }
          },
          filter: ->(parsed_value, item) {
            last_updated_day = get_offset_date(**parsed_value)

            return false unless last_updated_day.present?

            return !is_item_stale?(item, last_updated_day)
          }
        }
      }
    }

    @grammar.freeze
  end

  def validate_tokens(tokens)
    filtered_tokens = filter_tokens(tokens)
    invalid_tokens = tokens - filtered_tokens
    { valid: invalid_tokens.empty?, invalid_tokens: invalid_tokens }
  end

  # Remove tokens that are not valid in the context of the current Grammar
  def filter_tokens(tokens)
    # clone to prevent in-place mutation of values
    tokens.map(&:clone).select do |token|
      scope = token[:exclude] ? grammar[:negative] : grammar[:positive]
      keyword = token[:keyword]
      values = token[:values]

      next false unless scope[keyword] # filter incorrect keywords
      token[:values] =
      if scope[keyword][:_].is_a? Hash
        scope[keyword][:_][:validate].present? ? scope[keyword][:_][:validate].call(values) : values
      else
        values.select { |value| scope[keyword][value.to_sym].present? } # select correct values
      end

      next true unless token[:values].empty?
    end
  end

  def match_value(value, item, kw_scope)
    if kw_scope[:_].is_a?(Hash)
      parse = kw_scope[:_][:parse]

      parsed_value = parse&.call(value) || value
      filter = kw_scope[:_][:filter]

      if filter
        filter.call(parsed_value, item)
      else
        true
      end
    else
      filter = kw_scope[value.to_sym]
      true unless filter # ignore incorrect values if they are present at this point

      is_project_item = is_project_item?(item)
      if is_project_item && item.content
        filter.call(item.content)
      elsif !is_project_item
        filter.call(item)
      end
    end
  end

  sig do
    params(input: T::Enumerable[MemexProjectItem], field_id: Integer, field_value: String)
      .returns(T::Enumerable[MemexProjectItem])
  end
  def filter_items_by_field(input, field_id, field_value)
    target_column = T.must(MemexProjectColumn.find_by(id: field_id))
    input.select do |item|
      target_column.memex_project_column_values.find_by(memex_project_item: item)&.value == field_value
    end
  end

  def filter_items(input, query, **context)
    prefill_associations(input, query || "")

    repository_id = context[:repository_id]
    memex_project_owner = context[:memex_project_owner]

    tokens = Search::Memex::QueryParser.parse(query)
    filtered_tokens = filter_tokens(tokens)

    input.select do |item|
      next false if repository_id.present? && item.repository_id != repository_id

      result = filtered_tokens.all? do |token|
        scope = token[:exclude] ? grammar[:negative] : grammar[:positive]
        keyword = token[:keyword]
        values = token[:values]

        if token[:exclude] # if the token is negated
          values.all? do |value| # treat comma as AND operator
            match_value(value, item, scope[keyword])
          end
        else
          values.any? do |value| # treat comma as OR operator
            match_value(value, item, scope[keyword])
          end
        end
      end
    end
  end

  private def user_by_login(login)
    return false unless login

    @user_by_login ||= Hash.new do |hash, key|
      hash[key] = User.find_by_login(key)
    end
    @user_by_login[login]
  end

  private def prefill_association(items, association, **opts)
    GitHub::PrefillAssociations.prefill_associations(items, association, **opts)
  end

  private def prefill_project_item_associations(project_items, query)
    prefill_association(project_items, :content)
    prefill_associations(project_items.map(&:content), query)
  end

  private def prefill_issue_associations(issues, query)
    prefill_association(issues, :pull_request)
    if query.match(ASSIGNEE_QUALIFIER)
      prefill_association(issues, :assignees)
      # assignees are special because of the legacy assignee field; assigned_to? checks both assignees and assignee
      prefill_association(issues, :assignee, available_records: issues.map(&:assignees).flatten.uniq)
    end

    if query.match(LABEL_QUALIFIER)
      prefill_association(issues, :labels)
    end

    if query.match(MILESTONE_QUALIFIER)
      prefill_association(issues, :milestone)
    end

    if query.match(ISSUE_TYPE_QUALIFIER)
      GitHub::PrefillAssociations.prefill_batch_method(issues, :issue_type)
    end
  end

  private def prefill_pull_request_associations(pull_requests, query)
    prefill_association(pull_requests, :issue)
    prefill_issue_associations(pull_requests.map(&:issue), query)
  end

  private def prefill_associations(all_items, query)
    partitioned_items = all_items.group_by { |item| item.class.name }
    partitioned_items.each do |class_name, items|
      case class_name
      when "Issue"
        prefill_issue_associations(items, query)
      when "PullRequest"
        prefill_pull_request_associations(items, query)
      when "MemexProjectItem"
        prefill_project_item_associations(items, query)
      end
    end
  end

  private def normalized_target(item)
    is_project_item?(item) ? item.content : item
  end

  private def is_project_item?(item)
    item.is_a?(MemexProjectItem)
  end

  sig { params(range: Integer, unit: String).returns(T.nilable(Time)) }
  private def get_offset_date(range:, unit:)
    case unit
    when "d"
      range.days.ago.utc
    when "w"
      range.weeks.ago.utc
    when "m"
      range.months.ago.utc
    else
      nil
    end
  end

  sig { params(item: T.any(MemexProjectItem, Issue, PullRequest, DraftIssue), last_updated_day: Time).returns(T::Boolean) }
  private def is_item_stale?(item, last_updated_day)
    if item.is_a?(MemexProjectItem)
      (item.updated_at&.utc < last_updated_day) && (item.content&.updated_at&.utc < last_updated_day)
    else
      item.updated_at&.utc < last_updated_day
    end
  end
end
