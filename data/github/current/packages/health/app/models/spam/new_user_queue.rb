# typed: false
# frozen_string_literal: true

module Spam
  class NewUserQueue

    attr_accessor :spam_queue

    def initialize(spam_queue)
      @spam_queue = spam_queue
    end

    # Clear each User (or login) from the queue.
    def drop_these(u)
      list = Array(u)
      puts "In NewUserQueue#drop_these, dropping #{list.count} entries" if list.any?
      users, logins = list.partition { |t| t.respond_to? :id }
      # Dropping by id via GraphQL is so much faster it's worth doing all we can that way
      if logins.any?
        list = User.where(login: logins)
        users.concat list
        logins -= list.collect(&:login)
      end
      drop_these_by_user_id(users)
      bar = if logins.count < 100
        nil
      else
        ProgressBar.create(
              starting_at: 0,
              total: logins.count,
              format: "%a %e %c/%C (%j%%) %R |%B|",
              throttle_rate: 0.5,
              output: Rails.env.test? ? StringIO.new : STDERR,
            )
      end
      logins.each_with_index do |login, _idx|
        bar&.increment
        drop_this login
      end
      bar&.finish
      nil
    end

    def drop_these_by_user_id(users)
      pre_count = size
      users_count = users.count
      return 0 if users_count < 1
      print pink("Calling spam_queue_entries_for_users on %d users: \t" % users_count)
      t1 = Time.now
      results = spam_queue_entries_for_users(users, queue: spam_queue).collect { |t| t["id"] }
      t2 = Time.now
      interval = t2 - t1
      rate = users_count / interval
      results_count = results.count
      puts pink("%.02f/s (%d in %.02f sec.)" % [rate, users_count, interval])
      if results_count > 0
        puts "Dropping #{results_count} SQEs via #{blue('GraphQL')}"
        drop_spam_queue_entries(results)
        post_count = size
        puts Spam::Console.blue("In dtbui, dropped #{results_count}, so I reloaded: #{pre_count} -> #{post_count}.")
      end
      results_count
    end

    def drop_this(login)
      entries = entries_from_item(login)
      entry_count = entries.count
      entries.each { |t| t.drop actor: Spam::Console.my_bad_self }
      if entry_count > 0
        spam_queue.entries.reload
      end
      entry_count
    end

    # Grab the next non-Organization, possibly-non-spammy User from the queue
    # of spammy candidate logins.
    #
    # params[:all] - Don't skip Orgs or spammy users we find on the queue
    #
    # Returns User.
    def get_next(params = nil)
      params ||= {}
      get_all = params[:all]
      while (queue_size = self.size) > 0
        entry = get_next_entry(params[:from])
        unless user = entry.user
          entry.drop actor: Spam::Console.my_bad_self
          next
        end

        puts "\n#{queue_size} candidates in the queue (last: #{user.login})"

        if !get_all && (user.spammy? || user.organization?)
          skip_reason = user.spammy? ? "Spammy" : "Org"
          puts("Skipping #{user.login} - %s and get_all is false" % skip_reason)
          entry.drop actor: Spam::Console.my_bad_self
          sleep 0.2
        else
          return user
        end
      end
    end

    # Grab the next entry from front or end of list.
    def get_next_entry(from = nil)
      method = (from.to_s.start_with?("r")) ? :last : :first
      spam_queue.entries.reload.send(method)
    end

    def is_member?(item)
      entries_from_item(item).any?
    end

    def entries_from_item(item)
      if item.is_a? String
        spam_queue.entries.where(user_login: item)
      elsif item.is_a? Integer
        spam_queue.entries.where(user_id: item)
      elsif item.is_a? User
        spam_queue.entries.where("user_id = ? OR user_login = ?", item.id, item.login)
      end
    end

    def peek(number = 10)
      spam_queue.entries.reload.first number
    end

    # Add a User login to the queue
    #
    # user          - User or String containing a User login (will be downcased)
    # params[:onto] - Do lpush if "left" or "l"; otherwise rpush (default)
    #
    # Returns nothing.
    def push(users, params = nil)
      params ||= {}
      users = Array(users)
      users.each do |user|
        user = User.find_by_login(user) if user.is_a? String
        next unless user.is_a? User
        params[:user] = user

        begin
          spam_queue.entries.create params
        rescue ActiveRecord::RecordNotUnique
          # This user is already on the queue, discard the exception
        end
      end
      spam_queue.entries.reload if users.present?
      nil
    end

    # Drop `number` of items off the queue.
    def rdrop(number, from: nil)
      order = (from.to_s.start_with?("r")) ? "desc" : ""
      ids = spam_queue.entries.order("id #{order}").limit(number).pluck(:id)
      spam_queue.entries.where(id: ids).each { |t| t.drop actor: Spam::Console.my_bad_self }
    end

    # For each of `number` items on the queue, if `block` returns true,
    # drop it from the queue, or leave it otherwise.
    def rdump_if(number = 1, options = nil, &block)
      raise "This does not work as designed using NewUserQueue"
    end

    def rflag(number = 1)
      raise "This does not work as designed using NewUserQueue"
    end

    def get_count_query
      @get_count_query ||= <<-"GRAPHQL"
        query GetQueueEntryCount($queue_id: ID!) {
          spamQueues: node(id: $queue_id) {
            ... on SpamQueue {
              entries {
                totalCount
              }
            }
          }
        }
      GRAPHQL
    end

    def graphql_count
      variables = { "queue_id" => spam_queue.global_relay_id }
      results = gql get_count_query, variables: variables
      results.data.dig("spamQueues", "entries", "totalCount").to_i
    end
    # See how many items remain on the queue.
    alias_method :size, :graphql_count
    alias_method :count, :size
    alias_method :length, :size

  end
end
