#!/bin/bash


usage() {
  echo "Usage: $0 [-d] [software_version]"
  echo "  -d                Include dependencies in the SBOM"
  echo "  software_version  The version of the software (prompted if not provided)"
  exit 1
}

include_dependencies=false
while getopts ":d" opt; do
  case $opt in
    d)
      include_dependencies=true
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND - 1))


# Check if software version is passed as an argument
if [ -z "$1" ]; then
    while [[ -z "$software_version" ]]; do
        read -rp "Please enter the software version: " software_version
    done
else
  software_version="$1"
fi

today_date=$(date +%Y-%m-%d)

# Output file
output_file="gt450_cyclonedx_ubuntu_sbom_${today_date}_v${software_version}.json"

############### JSON file ###############
{
  echo "{"
  echo "  \"bomFormat\": \"CycloneDX\","
  echo "  \"Software Version\": \"$software_version\","
  echo "  \"Generated on Scanner SN\": \"$(hostname)\","
  echo "  \"components\": ["
} > $output_file

# Temporary file to hold dependencies
dep_file=$(mktemp)

# Get all installed packages with dpkg-query and format the output
dpkg-query -W -f='${binary:Package}, ${Version}, ${db:Status-Status}\n' |
while IFS=, read -r package version status; do
    package=$(echo "$package" | xargs)  
    version=$(echo "$version" | xargs)  
    description=$(dpkg-query -W -f='${Description}' $package)
    homepage=$(dpkg-query -W -f='${Homepage}' $package)

    # Escape double quotes, remove or escape newlines and carriage returns in description
    description=$(echo "$description" | sed 's/"/\\"/g' | tr -d '\n\r')

    # Append the component information to the JSON array
    echo "    {" >> $output_file
    echo "      \"type\": \"library\"," >> $output_file
    echo "      \"name\": \"${package}\"," >> $output_file
    echo "      \"version\": \"${version}\"," >> $output_file
    echo "      \"description\": \"${description}\"" >> $output_file

    if [ "$include_dependencies" = true ]; then
      # Fetch and process dependencies for the package
      apt-cache depends $package | grep "Depends:" | awk '{print $2}' > $dep_file
      # Dependencies Array
      dependsOn=()
      while read -r dep; do
        dep=$(echo "$dep" | xargs)  
        if [[ "$dep" != "$package" && ! " ${dependsOn[@]} " =~ " ${dep} " ]]; then
          dependsOn+=("\"$dep\"")
        fi
      done < $dep_file

      if [ ${#dependsOn[@]} -gt 0 ]; then
          # Add dependsOn for current package
          echo "      ,\"dependsOn\": [" >> $output_file
          IFS=,; echo "        ${dependsOn[*]}" >> $output_file
          unset IFS
          echo "      ]" >> $output_file
      fi
    fi

    echo "    }," >> $output_file
done

# Clean up for JSON format
sed -i '$ s/,$//' $output_file

{
  echo "  ]"
  echo "}"
} >> $output_file

rm $dep_file

echo "CycloneDX SBOM generated at $output_file"
