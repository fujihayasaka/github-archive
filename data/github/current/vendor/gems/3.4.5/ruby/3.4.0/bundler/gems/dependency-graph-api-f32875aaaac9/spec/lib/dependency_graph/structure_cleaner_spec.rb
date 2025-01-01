require "rails_helper"
require_relative "../../../lib/dependency_graph/structure_cleaner"

# Adapted from the test suite in the monolith:
# https://github.com/github/github/blob/master/test/lib/structure_cleaner_test.rb

describe DependencyGraph::StructureCleaner do
  it "clean_auto_increment strips out auto increment statements" do
    string = <<-SQL
CREATE TABLE `abilities` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `actor_id` int(11) NOT NULL,
  `actor_type` varchar(255) NOT NULL,
) ENGINE=InnoDB AUTO_INCREMENT=3417 DEFAULT CHARSET=utf8;
    SQL
    cleaned_string = described_class.clean_auto_increment(string)
    expect(cleaned_string).to_not match(/AUTO_INCREMENT=\d+/)
  end

  it "clean_auto_increment does not strip out auto increment columns" do
    string = <<-SQL
CREATE TABLE `abilities` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
) ENGINE=InnoDB AUTO_INCREMENT=3417 DEFAULT CHARSET=utf8;
    SQL
    cleaned_string = described_class.clean_auto_increment(string)
    expect(cleaned_string).to match(/int\(11\) NOT NULL AUTO_INCREMENT/)
  end

  it "clean_conditional_statements strips out conditional comments" do
    string = <<-SQL
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `abilities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
    SQL
    cleaned_string = described_class.clean_conditional_statements(string)
    expect(cleaned_string).to_not match(/\/\*!40101.*\*\//)
  end

  it "remove_table_definitions strips out the create and drop statements" do
    string = <<-SQL
DROP TABLE IF EXISTS `archived_assignments`;
CREATE TABLE `archived_assignments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `assignee_id` int(11) NOT NULL,
  `assignee_type` varchar(255) NOT NULL,
  `issue_id` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_archived_assignments_on_issue_id_assignee_id_assignee_type` (`issue_id`,`assignee_id`,`assignee_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    SQL
    cleaned_string = described_class.remove_table_definitions(string, ["archived_assignments"])
    expect(cleaned_string).to_not match(/DROP TABLE/)
    expect(cleaned_string).to_not match(/CREATE TABLE/)
  end

  it "remove_table_definitions removes all tables given" do
    string = <<-SQL
DROP TABLE IF EXISTS `email_messages`;
CREATE TABLE `email_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `message_id` varchar(255) NOT NULL,
  `message_data` mediumblob,
  PRIMARY KEY (`id`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `email_roles`;
CREATE TABLE `email_roles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `email_id` int(11) NOT NULL,
  `role` varchar(255) NOT NULL,
  `public` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `index_email_roles_on_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5707 DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `experiments`;
CREATE TABLE `experiments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `percent` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_experiments_on_name` (`name`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    SQL
    tables = %w(email_messages email_roles)
    cleaned_string = described_class.remove_table_definitions(string, tables)
    expect(cleaned_string).to_not match(/CREATE TABLE `email_messages`/)
    expect(cleaned_string).to_not match(/CREATE TABLE `email_roles`/)
    expect(cleaned_string).to match(/CREATE TABLE `experiments`/)
  end

  it "remove_table_definitions removes all tables matching a regex" do
    string = <<-SQL
DROP TABLE IF EXISTS `email_messages`;
CREATE TABLE `email_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `message_id` varchar(255) NOT NULL,
  `message_data` mediumblob,
  PRIMARY KEY (`id`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `email_roles`;
CREATE TABLE `email_roles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `email_id` int(11) NOT NULL,
  `role` varchar(255) NOT NULL,
  `public` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `index_email_roles_on_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5707 DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `email`;
CREATE TABLE `email` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `percent` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_experiments_on_name` (`name`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    SQL
    cleaned_string = described_class.remove_table_definitions(string, ["email_[^`]*"])
    expect(cleaned_string).to_not match(/CREATE TABLE `email_messages`/)
    expect(cleaned_string).to_not match(/CREATE TABLE `email_roles`/)
    expect(cleaned_string).to match(/CREATE TABLE `email`/)
  end

  it "extract_table_definitions extracts out the create and drop statements" do
    string = <<-SQL
DROP TABLE IF EXISTS `archived_assignments`;
CREATE TABLE `archived_assignments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `assignee_id` int(11) NOT NULL,
  `assignee_type` varchar(255) NOT NULL,
  `issue_id` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_archived_assignments_on_issue_id_assignee_id_assignee_type` (`issue_id`,`assignee_id`,`assignee_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `email`;
CREATE TABLE `email` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `percent` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_experiments_on_name` (`name`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    SQL
    output_string = described_class.extract_table_definitions(string, ["archived_assignments"])
    expect(output_string).to match(/DROP TABLE IF EXISTS `archived_assignments`/)
    expect(output_string).to match(/CREATE TABLE `archived_assignments` \(/)
    expect(output_string).to_not match(/CREATE TABLE `email`/)
  end

  it "extract_table_definitions extracts all tables given" do
    string = <<-SQL
DROP TABLE IF EXISTS `email_messages`;
CREATE TABLE `email_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `message_id` varchar(255) NOT NULL,
  `message_data` mediumblob,
  PRIMARY KEY (`id`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `email_roles`;
CREATE TABLE `email_roles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `email_id` int(11) NOT NULL,
  `role` varchar(255) NOT NULL,
  `public` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `index_email_roles_on_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5707 DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `experiments`;
CREATE TABLE `experiments` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `percent` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_experiments_on_name` (`name`),
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
    SQL
    tables = %w(email_messages email_roles)
    output_string = described_class.extract_table_definitions(string, tables)
    expect(output_string).to match(/CREATE TABLE `email_messages`/)
    expect(output_string).to match(/CREATE TABLE `email_roles`/)
    expect(output_string).to_not match(/CREATE TABLE `experiments`/)
  end
end
