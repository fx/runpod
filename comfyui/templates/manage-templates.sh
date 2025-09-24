#!/bin/bash
set -e

# Template management script for RunPod
# Handles listing, updating, and creating templates

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if API key is provided or available
if [ -z "$RUNPOD_API_KEY" ]; then
    if [ -f ~/.runpod/config.toml ]; then
        export RUNPOD_API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)
    else
        echo -e "${RED}Error: RUNPOD_API_KEY not set and ~/.runpod/config.toml not found${NC}"
        echo "Please set RUNPOD_API_KEY environment variable or run: runpodctl config --apiKey <your-key>"
        exit 1
    fi
fi

API_URL="https://rest.runpod.io/v1/templates"

# Function to list templates
list_templates() {
    echo -e "${GREEN}Fetching RunPod templates...${NC}"
    response=$(curl -s -X GET "$API_URL" -H "Authorization: Bearer $RUNPOD_API_KEY")

    if [ "$1" == "--json" ]; then
        echo "$response" | jq '.'
    else
        echo -e "\n${GREEN}ComfyUI Templates:${NC}"
        echo "$response" | jq -r '.[] | select(.name | contains("ComfyUI")) | "  \(.id): \(.name) [\(.imageName)]"'

        echo -e "\n${GREEN}Other Templates:${NC}"
        echo "$response" | jq -r '.[] | select(.name | contains("ComfyUI") | not) | "  \(.id): \(.name) [\(.imageName)]"'
    fi
}

# Function to update templates
update_templates() {
    echo -e "${GREEN}Starting RunPod template update...${NC}\n"

    # Get directory containing this script
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Process all template JSON files
    for template_file in "$SCRIPT_DIR"/runpod-template*.json; do
        [ ! -f "$template_file" ] && continue

        echo -e "${YELLOW}Processing: $(basename "$template_file")${NC}"

        template_name=$(jq -r '.name' "$template_file")

        # Convert template to API format
        template_json=$(jq '{
            name: .name,
            imageName: .imageName,
            ports: (if .ports | type == "string" then [.ports] else .ports end),
            volumeInGb: .volumeInGb,
            volumeMountPath: .volumeMountPath,
            env: (.env | if type == "array" then
                map({(.key): .value}) | add
            else . end),
            containerDiskInGb: .containerDiskInGb
        }' "$template_file")

        # Get existing template ID if exists
        existing=$(curl -s -X GET "$API_URL" \
            -H "Authorization: Bearer $RUNPOD_API_KEY" | \
            jq -r ".[] | select(.name == \"$template_name\") | .id" | head -1)

        # Update if exists, otherwise create
        if [ -n "$existing" ] && [ "$existing" != "null" ]; then
            echo "  Updating existing template ID: $existing"
            response=$(curl -s -X PATCH "$API_URL/$existing" \
                -H "Authorization: Bearer $RUNPOD_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$template_json")

            if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
                echo -e "  ${GREEN}✅ Updated ID: $existing${NC}"
            else
                echo -e "  ${RED}❌ Update failed: $response${NC}"
            fi
        else
            echo "  Creating new template: $template_name"
            response=$(curl -s -X POST "$API_URL" \
                -H "Authorization: Bearer $RUNPOD_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$template_json")

            if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
                new_id=$(echo "$response" | jq -r '.id')
                echo -e "  ${GREEN}✅ Created with ID: $new_id${NC}"
            else
                echo -e "  ${RED}❌ Create failed: $response${NC}"
            fi
        fi

        echo ""
    done

    echo -e "${GREEN}Complete!${NC}"
}

# Function to get detailed template info
get_template() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Template ID required${NC}"
        echo "Usage: $0 get <template-id>"
        exit 1
    fi

    echo -e "${GREEN}Fetching template $1...${NC}"
    curl -s -X GET "$API_URL" \
        -H "Authorization: Bearer $RUNPOD_API_KEY" | \
        jq ".[] | select(.id == \"$1\")"
}

# Function to show help
show_help() {
    cat << EOF
RunPod Template Management Script

Usage:
  $0 [command] [options]

Commands:
  list            List all templates (default if no command given)
  list --json     List templates in JSON format
  update          Update/create templates from JSON files
  get <id>        Get detailed info for a specific template
  help            Show this help message

Environment:
  RUNPOD_API_KEY  RunPod API key (or stored in ~/.runpod/config.toml)

Examples:
  $0              # List all templates
  $0 list         # List all templates
  $0 update       # Update templates from JSON files
  $0 get abc123   # Get details of template with ID abc123

Template files should be in the same directory as this script
and named runpod-template*.json
EOF
}

# Main command handling
case "${1:-list}" in
    list)
        list_templates "${2:-}"
        ;;
    update)
        update_templates
        ;;
    get)
        get_template "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac