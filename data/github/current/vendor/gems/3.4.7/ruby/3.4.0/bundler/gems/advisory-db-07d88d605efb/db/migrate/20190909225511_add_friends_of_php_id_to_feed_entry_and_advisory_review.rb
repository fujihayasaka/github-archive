# frozen_string_literal: true

class AddFriendsOfPHPIDToFeedEntryAndAdvisoryReview < ActiveRecord::Migration[5.2]
  # Add support for FriendsOfPHP Advisories
  # add friends_of_php_id to FeedEntry and AdvisoryReview
  # Do not in this case case add the id into Advisory
  # This is because the fohphp id is not published publicly, it is internal only
  #
  # Length:
  # The ID is based on path of the file in the repo
  # The longest current path is 63 characters:
  # I used this cmd to determine that: $ ls **/*.yaml | awk '{ print length($0) " " $0; }' | sort
  #
  # there is however no reason a much longer path/ID could not happen
  # Therefore, the column size will add some padding.
  # By using the path in the identifier, it is very user friendly.
  # We could however use the sha of the path, or something like that to get a fixed length ID?
  def change
    add_column :advisory_reviews, :friends_of_php_id, :string, limit: 100
    add_index :advisory_reviews, :friends_of_php_id, unique: true

    add_column :feed_entries, :friends_of_php_id, :string, limit: 100
    add_index :feed_entries, :friends_of_php_id
  end
end
