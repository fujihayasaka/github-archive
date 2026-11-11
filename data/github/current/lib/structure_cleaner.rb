# typed: true
# frozen_string_literal: true

# A class with methods to help clean up the mysqldump output
class StructureCleaner
  # Public: strip out AUTO_INCREMENT
  #
  # Returns the given string with
  # AUTO_INCREMENT statements removed
  def self.clean_auto_increment(string)
    string.gsub(/\s*AUTO_INCREMENT=\d+(.*?;)$/, "\\1")
  end

  # Public: strip out conditional statements like:
  # /*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
  #
  # Returns the given string with the comments
  # removed
  def self.clean_conditional_statements(string)
    string.gsub(/^\/\*.*\*\/;$\n/, "")
  end

  # Public: MySQL 8.0.29+ will always print utf8mb3 instead of utf8 so replace it
  # with utf8mb3 to be consistent
  #
  # Returns the given string with the utf8 replaced by utf8mb3
  def self.replace_utf8_with_utf8mb3(string)
    string = string.gsub(/(CHAR(ACTER )?SET[=\s])utf8\b/, "\\1utf8mb3")
    string.gsub(/(COLLATE[=\s])utf8_/, "\\1utf8mb3_")
  end

  # Public: make PARTITIONS consistent
  #
  # Returns the given string with PARTITIONS entries always set to 2
  def self.clean_partitions_comment(string)
    string.gsub(%r{^PARTITIONS \d+ \*/;}, "PARTITIONS 2 */;\n-- partitions are always set to 2 for consistency checks but may differ in production.")
  end

  # MySQL 8.0.28+ is inconsistent about whether it prints
  #     varchar(x) CHARACTER SET utf8mb4 COLLATE utf8mb4_xxx
  # or just
  #     varchar(x) COLLATE utf8mb4_xxx
  #
  # To avoid spurious diffs, we remove the CHARACTER SET part
  # since it is redundant
  def self.remove_unnecessary_column_character_set(string)
    string.gsub(/\bCHARACTER SET (\S+) (COLLATE \1_\S+?)\b/, '\2')
  end

  # Public: strip out blank lines
  #
  # Returns the given string with blank lines removed
  def self.remove_blank_lines(string)
    string.gsub(/^\s*$\n/, "")
  end

  # Public: extract the CREATE TABLE and DROP TABLE
  # statements from the string for the given tables
  #
  # tables - array of string table names or regexes
  #
  # Returns a string with the statements of the given tables
  def self.extract_table_definitions(string, tables)
    output = ""
    tables.sort.each do |table|
      output += string.match(/^DROP TABLE IF EXISTS `(?:#{table})`;$\n/).to_s
      output += string.match(/^CREATE TABLE `(?:#{table})`.+?(?<!;\n);\n/m).to_s
    end
    output
  end

  # Public: remove the CREATE TABLE and DROP TABLE
  # statements from the string for the given tables
  #
  # tables - array of strings of table names (strings may contain regex syntax to match multiple tables)
  #
  # Returns the given string with the given tables
  # removed
  def self.remove_table_definitions(string, tables)
    output = string.gsub(/^CREATE TABLE `(?:#{tables.join("|")})`.+?(?<!;\n);\n/m, "")
    output.gsub(/^DROP TABLE IF EXISTS `(?:#{tables.join("|")})`;$\n/, "")
  end
end
