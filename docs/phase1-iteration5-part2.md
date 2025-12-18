# Phase 1 – Iteration 6: Provider Management & Token Generation

**Scope:** Enhanced provider settings with danger zone operations, provider types & auth types configuration UI, compatible providers relationship, and Gitea token generation with username/password.

## Key Changes

### 1. Provider Settings - Danger Zone

**File:** `lib/service_hub_web/live/provider_live/form.ex`

Implemented modal-based dangerous operations for provider settings to prevent accidental destructive changes:

**Danger Zone Features:**
- **Delete Provider** - Permanent deletion with confirmation
- **Change Provider Type** - Switch provider type with warning about service compatibility
- **Change Base URL** - Update API endpoint with warning about connection impact
- Modal dialogs with explicit confirmation for each operation
- Disabled fields in edit mode (provider_type, base_url) - changes only via danger zone
- Event handlers: `confirm-change-type`, `confirm-change-url`, `confirm-delete`, `execute-danger`

**Implementation Pattern:**
- Shows danger zone only in `:edit` action
- Uses DaisyUI modal classes for dialog
- State management with assigns: `show_danger_modal`, `danger_action`, `danger_modal_title`, `danger_modal_message`, `danger_form`
- Separate form for danger operations to avoid conflicts with main provider form

### 2. Provider Types UI

**Created Files:**
- `lib/service_hub_web/live/provider_type_live/index.ex` - List view
- `lib/service_hub_web/live/provider_type_live/form.ex` - Create/Edit form

**Index View Features:**
- Professional card-based layout instead of table
- Shows provider type name, key badge, and required_fields as individual badges
- Empty state with call-to-action button
- Minimal design with proper spacing and hover effects

**Form Features:**
- Name and key inputs
- JSON textarea for required_fields configuration
- Example provided for Gitea configuration structure
- Validation and error handling
- Enhanced layout with max-width and better spacing

**Router Updates:**
- Added routes under `/config/provider_types` scope
- Integrated with `:require_authenticated_user` live_session

**Sidebar Integration:**
- Added "System" section in sidebar navigation
- Links to Provider Types and Auth Types management

### 3. Provider-Specific Authentication Sections

**GitHub Authentication Section:**
- OAuth connection option (reuses existing GitHub connection)
- "Use my GitHub connection" button applies token from connected account
- Manual auth type selector as alternative
- Shows connection scope information
- State: `use_github_connection`, `github_connection`

**Gitea Authentication Section:**
- Token generation UI with username/password inputs
- Generates Gitea access token via API without requiring pre-existing token
- Automatically applies generated token to auth_data
- Auto-selects "token" auth type when generating
- Clear messaging: "Use your Gitea username (not email)"
- State: `gitea_username`, `gitea_password`, `gitea_token_generated`, `gitea_token_error`

**Implementation Details:**
- Inputs use `phx-blur` to capture values in LiveView assigns
- No nested forms - inputs outside main provider form to prevent submission conflicts
- Button triggers `generate-gitea-token` event
- Handler calls `ServiceHub.ProviderAdapters.Gitea.create_token/4`
- Enhanced error handling:
  - `:unauthorized` → "Invalid username or password"
  - `404` → "User not found. Use your Gitea username, not email."
  - Generic errors with detailed messages

### 4. Compatible Providers Relationship

**Problem Solved:**
Auth types were showing for all providers regardless of compatibility (e.g., GitHub OAuth showing for Gitea).

**Database Migration:**
- File: `priv/repo/migrations/20251218035140_add_compatible_providers_to_auth_types.exs`
- Added `compatible_providers` field to `auth_types` table
- Type: `{:array, :string}` with default `[]`

**Schema Updates:**
- `lib/service_hub/providers/auth_type.ex`:
  - Added field: `compatible_providers, {:array, :string}, default: []`
  - Updated changeset to cast compatible_providers
  - Modified `apply_registry_defaults` to set compatible_providers from registry

**Registry Updates:**
- `lib/service_hub/providers/auth_registry.ex`:
  - Added `compatible_providers` to each auth type definition
  - `token`: `["gitea"]`
  - `github_pat`, `github_app`, `github_oauth`: `["github"]`

**Form Filtering:**
- `filter_auth_types/2` in provider form
- Strict filtering: empty `compatible_providers` = not shown for ANY provider
- No "show all if empty" logic - explicit relationships required

### 5. Auth Types Configuration UI

**File:** `lib/service_hub_web/live/auth_type_live/form.ex`

**Features:**
- State-based checkbox selector for compatible providers
- "Select All" button for convenience
- Visual feedback for selected providers
- JSON serialization for form submission
- Helper function: `decode_compatible_providers/1` parses JSON on save

**Implementation:**
- Loads all provider_types in mount
- State managed via `@selected_providers` array
- Event handlers: `toggle-provider`, `select-all-providers`
- Hidden input with `Jason.encode!(@selected_providers)` for form submission
- Server-side parsing and validation

### 6. Case-Insensitive Provider Key Matching

**Problem:** Provider key comparisons were case-sensitive (e.g., "Gitea" vs "gitea").

**Solution:**
- All provider_key comparisons now use `String.downcase/1`
- Applied in provider form sections for GitHub and Gitea
- Ensures provider-specific UI appears regardless of key casing

### 7. Service Form Bug Fixes

**File:** `lib/service_hub_web/live/service_live/form_component.ex`

**Fixed Issues:**
1. **FunctionClauseError** - `save_service/3` expecting `:new_service` but receiving `:new`
   - Solution: Changed guards to accept both variations
   - `when action in [:new, :new_service]`
   - `when action in [:edit, :edit_service]`

2. **push_patch Error** - Cannot push_patch when navigating between different root views
   - Solution: Changed from `push_patch` to `push_navigate`
   - Allows proper navigation from LiveComponent to different LiveView

## Technical Patterns

### Modal-Based Dangerous Operations
```elixir
# Trigger modal
phx-click="confirm-change-type"

# Modal state
@show_danger_modal = true
@danger_action = :change_type
@danger_modal_title = "Change Provider Type"
@danger_form = to_form(%{})

# Execute after confirmation
def handle_event("execute-danger", params, socket) do
  case socket.assigns.danger_action do
    :delete -> delete_provider()
    :change_type -> update_provider(params)
    :change_url -> update_provider(params)
  end
end
```

### State-Based Input Capture (No Nested Forms)
```elixir
# Inputs outside main form
<input phx-blur="update-gitea-username" value={@gitea_username} />
<input phx-blur="update-gitea-password" value={@gitea_password} />
<button phx-click="generate-gitea-token">Generate</button>

# Handlers update state
def handle_event("update-gitea-username", %{"value" => value}, socket) do
  {:noreply, assign(socket, :gitea_username, value)}
end

# Button reads from state
def handle_event("generate-gitea-token", _params, socket) do
  username = socket.assigns.gitea_username
  password = socket.assigns.gitea_password
  # ... use values
end
```

### Gitea Token Generation Flow
```elixir
# Call adapter directly
case ServiceHub.ProviderAdapters.Gitea.create_token(
  socket.assigns.provider,
  username,
  password,
  %{name: "ServiceHub - #{socket.assigns.provider.name}"}
) do
  {:ok, token} ->
    # Update changeset with token
    params = put_in(params, ["auth_data", "token"], token)
    # Auto-select token auth type
    params = maybe_put_token_auth_type(params, auth_types)
    # Apply to form
    assign_form(socket, Providers.change_provider(..., params))
end
```

### JSON Array Serialization for Checkboxes
```elixir
# Hidden input with serialized array
<input type="hidden" name="auth_type[compatible_providers]" 
       value={Jason.encode!(@selected_providers)} />

# Server-side parsing
defp decode_compatible_providers(value) when is_binary(value) do
  case Jason.decode(value) do
    {:ok, list} when is_list(list) -> list
    _ -> []
  end
end
```

## Files Modified

### Core Functionality
- `lib/service_hub_web/live/provider_live/form.ex` - Danger zone, Gitea token generation, auth filtering
- `lib/service_hub_web/live/service_live/form_component.ex` - Action guard fixes, navigation fix

### New UI Components
- `lib/service_hub_web/live/provider_type_live/index.ex` - Provider types list
- `lib/service_hub_web/live/provider_type_live/form.ex` - Provider types form
- `lib/service_hub_web/live/auth_type_live/form.ex` - Auth types form with checkboxes

### Schema & Registry
- `lib/service_hub/providers/auth_type.ex` - Added compatible_providers field
- `lib/service_hub/providers/auth_registry.ex` - Added compatible_providers metadata

### Layout & Navigation
- `lib/service_hub_web/components/layouts/sidebar.ex` - Added System section

### Database
- `priv/repo/migrations/20251218035140_add_compatible_providers_to_auth_types.exs`

## Testing Notes

### Danger Zone
- Edit existing provider → danger zone appears at bottom
- Cannot edit provider_type or base_url directly (disabled fields)
- Delete provider → modal confirmation → redirects to providers list
- Change type → modal with dropdown → updates provider type
- Change URL → modal with input → updates base URL

### Provider Types & Auth Types
- Navigate to /config/provider_types
- Create new provider type with name, key, and required_fields JSON
- Example JSON structure provided in form
- Compatible providers selected via checkboxes in auth type form
- "Select All" button works correctly

### Token Generation
1. Create Gitea provider type (key: "gitea")
2. Create "token" auth type with compatible_providers: ["gitea"]
3. Create new provider, select Gitea type
4. Save provider first (required - needs base_url)
5. Edit provider
6. In Gitea section, enter username (NOT email) and password
7. Click "Generate Token"
8. Token applied to auth_data, auth type auto-selected
9. Click "Save Provider" to persist changes

### Auth Types Filtering
- Only compatible auth types show for each provider
- Empty compatible_providers = auth type hidden for all providers
- Filtering is case-insensitive for provider keys

## Known Limitations

1. **Token Generation Requires Saved Provider** - Must save provider first to have base_url available
2. **No Token Revocation UI** - Generated tokens cannot be revoked from UI (must do in Gitea)
3. **phx-blur Required** - Username/password inputs need blur event to capture values
4. **No Real-Time Validation** - Token generation validates only on submit, not while typing

## Next Steps

1. Test token generation with real Gitea instance
2. Consider adding token revocation flow
3. Implement similar patterns for GitHub App authentication
4. Add validation preview for auth_data before saving
5. Create monitoring dashboard for service × client matrix
6. Implement CRUD for Clients (`/config/clients`)
7. Build services list view with installations
8. Create audit log viewer
