#!/bin/bash

# Script to find .graphql exports in all package.json files under ui/packages
# Usage: ./find-graphql-exports.sh

echo "Searching for .graphql exports in ui/packages..."
echo "=================================================="
echo

# Find all package.json files in ui/packages and process them
find ui/packages -name "package.json" -type f | while read -r package_file; do
    # Extract package name from the package.json
    package_name=$(grep -o '"name": "[^"]*"' "$package_file" | cut -d'"' -f4)

    # Get the directory path
    package_path=$(dirname "$package_file")

    # Find lines containing .graphql
    graphql_lines=$(grep -n '\.graphql' "$package_file")

    # If we found any .graphql lines, output them grouped by package
    if [ ! -z "$graphql_lines" ]; then
        echo "Package: $package_name ($package_file)"
        echo "Path: $package_path"
        echo "GraphQL exports:"

        # Process each line to add the search string
        echo "$graphql_lines" | while IFS= read -r line; do
            # Extract the export name (the key before the colon, removing ./ prefix)
            export_name=$(echo "$line" | sed 's/^[0-9]*://; s/^[[:space:]]*"\.\/\([^"]*\)".*/\1/')
            search_string="$package_name/$export_name"
            echo "  $line ($search_string)"
        done
        echo
    fi
done

echo "Search completed."
