#!/bin/bash

# VSCode Extension Ban Tool for Linux/macOS
# This script lists all installed VSCode extensions and lets you ban one by selection

echo "VSCode Extension Ban Tool (Linux/macOS)"
echo "====================================="

# Define possible VSCode extension locations based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS locations
    VSCODE_LOCATIONS=(
        "$HOME/.vscode/extensions"
        "$HOME/Library/Application Support/Code/User/extensions"
        "$HOME/.vscode-insiders/extensions"
        "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions"
    )
else
    # Linux locations
    VSCODE_LOCATIONS=(
        "$HOME/.vscode/extensions"
        "$HOME/.config/Code/User/extensions"
        "$HOME/.vscode-insiders/extensions"
        "/usr/share/code/resources/app/extensions"
        "/usr/share/vscode/resources/app/extensions"
    )
fi

# Create temporary file for extension list
TEMP_FILE="/tmp/vscode_extensions_list.txt"
> "$TEMP_FILE"  # Clear the file if it exists

echo "Searching for installed extensions..."
echo

# Find all extensions and put them in an array
EXTENSIONS=()
EXTENSION_PATHS=()
EXTENSION_IDS=()
COUNTER=0

for LOCATION in "${VSCODE_LOCATIONS[@]}"; do
    if [ -d "$LOCATION" ]; then
        for EXT_PATH in "$LOCATION"/*; do
            if [ -d "$EXT_PATH" ]; then
                # Skip hidden directories, blocker and disabled extensions
                EXT_NAME=$(basename "$EXT_PATH")
                if [[ ! "$EXT_NAME" =~ ^\. && ! "$EXT_NAME" =~ blocker && ! "$EXT_NAME" =~ disabled ]]; then
                    # Try to get friendly name from package.json
                    FRIENDLY_NAME="Unknown"
                    if [ -f "$EXT_PATH/package.json" ]; then
                        if command -v jq >/dev/null 2>&1; then
                            FRIENDLY_NAME=$(jq -r '.displayName // .name // "Unknown"' "$EXT_PATH/package.json")
                        else
                            # Fallback if jq is not available
                            FRIENDLY_NAME=$(grep -o '"displayName"[^,]*' "$EXT_PATH/package.json" | cut -d'"' -f4)
                            if [ -z "$FRIENDLY_NAME" ]; then
                                FRIENDLY_NAME=$(grep -o '"name"[^,]*' "$EXT_PATH/package.json" | cut -d'"' -f4)
                            fi
                        fi
                    fi
                    
                    # Get extension ID
                    EXTENSION_ID="$EXT_NAME"
                    
                    # Add to lists
                    COUNTER=$((COUNTER + 1))
                    EXTENSIONS+=("$FRIENDLY_NAME ($EXT_NAME)")
                    EXTENSION_PATHS+=("$EXT_PATH")
                    EXTENSION_IDS+=("$EXTENSION_ID")
                    
                    echo "$COUNTER. $FRIENDLY_NAME ($EXT_NAME)"
                    echo "$COUNTER. $FRIENDLY_NAME ($EXT_NAME)" >> "$TEMP_FILE"
                fi
            fi
        done
    fi
done

echo

if [ $COUNTER -eq 0 ]; then
    echo "No extensions found."
    exit 0
fi

# Ask user which extension to ban
read -p "Enter the number of the extension you want to ban (1-$COUNTER): " SELECTION

# Validate input
if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt $COUNTER ]; then
    echo "Invalid selection."
    exit 1
fi

# Adjust for zero-based array indexing
INDEX=$((SELECTION - 1))

# Get the selected extension details
SELECTED_PATH="${EXTENSION_PATHS[$INDEX]}"
SELECTED_NAME="${EXTENSIONS[$INDEX]}"
SELECTED_ID="${EXTENSION_IDS[$INDEX]}"

echo
echo "You selected: $SELECTED_NAME"
echo "Located at: $SELECTED_PATH"
echo
read -p "Are you sure you want to ban this extension? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo
echo "Banning extension $SELECTED_NAME..."

# Ban the extension using multiple methods
echo "Disabling extension..."

# 1. Make package.json invalid
if [ -f "$SELECTED_PATH/package.json" ]; then
    echo "Modifying extension package.json to make it invalid"
    mv "$SELECTED_PATH/package.json" "$SELECTED_PATH/package.json.disabled"
    echo "Created: $SELECTED_PATH/package.json.disabled"
fi

# 2. Create blocker files in all possible locations
echo "Creating blockers..."
for LOCATION in "${VSCODE_LOCATIONS[@]}"; do
    if [ -d "$LOCATION" ]; then
        BLOCKER_DIR="$LOCATION/${SELECTED_ID}.blocker"
        mkdir -p "$BLOCKER_DIR"
        echo "This extension has been blocked by administrator." > "$BLOCKER_DIR/BLOCKED"
        chmod 444 "$BLOCKER_DIR/BLOCKED"  # Read-only
        echo "Created blocker at: $BLOCKER_DIR"
    fi
done

# 3. Rename the extension directory
mv "$SELECTED_PATH" "${SELECTED_PATH}.disabled"
echo "Renamed directory to: ${SELECTED_PATH}.disabled"

# 4. Update VSCode settings.json to add extension to disallowedExtensions
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS settings location
    SETTINGS_FILE="$HOME/Library/Application Support/Code/User/settings.json"
else
    # Linux settings location
    SETTINGS_FILE="$HOME/.config/Code/User/settings.json"
fi

if [ -f "$SETTINGS_FILE" ]; then
    echo "Adding extension to VSCode blacklist in user settings"
    
    # Create backup
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup"
    echo "Backup created: ${SETTINGS_FILE}.backup"
    
    # Process settings.json to add the extension to disallowedExtensions
    if command -v jq >/dev/null 2>&1; then
        # Use jq if available
        if jq '.["extensions.disallowedExtensions"]' "$SETTINGS_FILE" > /dev/null 2>&1; then
            # If disallowedExtensions exists, add to it
            jq --arg extid "$SELECTED_ID" '."extensions.disallowedExtensions" += [$extid]' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        else
            # If disallowedExtensions doesn't exist, create it
            jq --arg extid "$SELECTED_ID" '. + {"extensions.disallowedExtensions": [$extid]}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
        fi
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    else
        # Manual edit if jq is not available
        if grep -q "\"extensions.disallowedExtensions\"" "$SETTINGS_FILE"; then
            # Already has disallowedExtensions, add to it
            sed -i.bak "s/\"extensions.disallowedExtensions\":\s*\[/\"extensions.disallowedExtensions\": \[\"$SELECTED_ID\", /" "$SETTINGS_FILE"
        else
            # Add new disallowedExtensions array
            sed -i.bak "s/{/{\"extensions.disallowedExtensions\": \[\"$SELECTED_ID\"\], /" "$SETTINGS_FILE"
        fi
    fi
    
    echo "Updated settings.json to blacklist $SELECTED_ID"
fi

echo
echo "====================================="
echo "Extension $SELECTED_NAME has been successfully banned!"
echo "Users will not be able to install or use this extension."
echo
echo "Note: For complete blocking, you may need to:"
echo "1. Run this script with sudo for system-wide effect"
echo "2. Restart VSCode if it's currently running"
echo "3. Consider using organizational policies for company-wide blocking"
echo

exit 0
