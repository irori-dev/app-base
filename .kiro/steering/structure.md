# Project Structure & Conventions

## Directory Organization

### Application Structure
```
app/
├── controllers/
│   ├── admins/              # Admin namespace controllers
│   ├── users/               # User namespace controllers  
│   └── concerns/            # Shared controller logic
├── models/
│   ├── user/                # User namespace models
│   │   ├── core.rb          # Main user model
│   │   ├── email_change.rb  # Email change functionality
│   │   └── password_reset.rb # Password reset functionality
│   ├── concerns/            # Shared model logic
│   └── notifier/            # Notification services
├── components/              # ViewComponent classes
│   ├── admins/              # Admin-specific components
│   ├── users/               # User-specific components
│   └── [shared components]  # Reusable UI components
├── views/
│   ├── admins/              # Admin view templates
│   ├── users/               # User view templates
│   └── svgs/                # SVG icon partials
├── jobs/                    # Background job classes
└── javascript/
    └── controllers/         # Stimulus controllers
```

### Database Schema Management
```
db/
└── schema/                  # Ridgepole schema files
    ├── primary/             # Main application data
    │   ├── Schemafile       # Schema configuration
    │   ├── admins.schema    # Admin table definition
    │   ├── user_cores.schema # User table definition
    │   └── [other].schema   # Additional tables
    ├── cache/               # Solid Cache tables
    └── queue/               # Solid Queue tables
```

### Testing Structure
```
spec/
├── components/              # ViewComponent tests
├── controllers/             # Controller tests
├── models/                  # Model tests
├── requests/                # Request/API tests
├── system/                  # End-to-end tests
├── factories/               # FactoryBot definitions
└── support/                 # Test helpers and configuration
```

## Naming Conventions

### Models
- **Namespaced Models**: Use modules for logical grouping (e.g., `User::Core`, `User::PasswordReset`)
- **Table Names**: Follow namespace with underscore prefix (`user_cores`, `user_password_resets`)
- **Concerns**: Descriptive names ending in behavior (`Authenticatable`, `Tokenizable`)

### Controllers
- **Namespace Separation**: `Admins::` and `Users::` for different user types
- **Base Controllers**: `Admins::BaseController`, `Users::BaseController` for shared logic
- **RESTful Actions**: Follow Rails conventions (index, show, new, create, edit, update, destroy)

### Components
- **Directory Structure**: `app/components/[namespace]/[component_name]/`
- **File Naming**: `component.rb` and `component.html.haml` in component directory
- **Class Naming**: `[Namespace]::[ComponentName]::Component`

### Views
- **Partials**: Prefix with underscore (`_form.html.haml`)
- **Turbo Streams**: Suffix with `.turbo_stream.haml`
- **Layouts**: Namespace-specific layouts in `layouts/` subdirectories

## Code Organization Patterns

### Concerns Usage
- **Models**: Extract shared behavior into concerns (`Authentication`, `Tokenizable`)
- **Controllers**: Common functionality in concerns (`Authenticatable`, `Searchable`)
- **Placement**: Always in `app/models/concerns/` or `app/controllers/concerns/`

### Authentication Architecture
- **Dual System**: Completely separate user and admin authentication
- **Session Management**: Independent session keys and logic
- **Shared Logic**: Common authentication patterns in `Authenticatable` concern

### Component Architecture
- **ViewComponent**: Prefer components over partials for reusable UI elements
- **Testing**: Each component should have corresponding spec file
- **Styling**: Use Tailwind classes within component templates

## File Naming Standards

### Ruby Files
- **Snake Case**: All Ruby files use snake_case
- **Descriptive Names**: Clear, descriptive file and class names
- **Namespace Directories**: Match module structure with directory structure

### View Files
- **Template Extensions**: `.html.haml` for templates, `.turbo_stream.haml` for Turbo responses
- **Partial Prefix**: Underscore prefix for partial templates
- **Component Structure**: Component files in dedicated subdirectories

### JavaScript Files
- **Stimulus Controllers**: `[name]_controller.js` in `app/javascript/controllers/`
- **Camel Case**: JavaScript follows camelCase conventions
- **Descriptive Names**: Controller names should describe their purpose

## Configuration Patterns

### Environment Management
- **Rails Credentials**: Use `rails credentials:edit` for sensitive configuration
- **Environment Variables**: For deployment-specific settings
- **Locale**: Default to Japanese (`ja`) with English fallback

### Database Configuration
- **Multi-Database**: Separate databases for cache, queue, and primary data
- **Schema Management**: Use Ridgepole instead of Rails migrations
- **Naming**: Descriptive table and column names following Rails conventions

### Route Organization
- **Namespace Separation**: Clear separation between admin and user routes
- **RESTful Design**: Follow REST principles for resource routes
- **Nested Resources**: Use judiciously, prefer shallow nesting when possible