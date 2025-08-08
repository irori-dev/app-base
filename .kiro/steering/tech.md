# Technology Stack

## Core Technologies

- **Ruby 3.4.5** / **Rails 8.0.2**
- **PostgreSQL 16** - Primary database for all environments
- **Solid Suite** - Database-backed alternatives to Redis/Sidekiq
  - Solid Cache - Caching layer
  - Solid Queue - Background job processing
  - Solid Cable - WebSocket connections

## Frontend Stack

- **Hotwire** - Modern SPA-like experience without complex JavaScript
  - Turbo Drive - Fast page navigation
  - Turbo Frames - Partial page updates
  - Turbo Streams - Real-time updates
  - Stimulus - Lightweight JavaScript framework
- **Tailwind CSS** - Utility-first CSS framework with hot reload
- **ViewComponent** - Component-based view architecture
- **ImportMap** - JavaScript module management (no node_modules required)
- **Haml** - Template engine for cleaner markup

## Key Libraries

- **Authentication**: bcrypt for secure password hashing
- **Database**: Ridgepole for schema management
- **Pagination**: Kaminari
- **Search**: Ransack
- **Email**: Letter Opener Web (development preview)
- **Notifications**: Exception Notification + Slack integration
- **Testing**: RSpec, FactoryBot, Capybara, WebMock
- **Code Quality**: RuboCop, Brakeman, Bullet (N+1 detection)

## Development Environment

- **Docker Compose** - Containerized development environment
- **VS Code DevContainer** - Consistent development setup
- **PostgreSQL** - Database for all environments (dev/test/prod)

## Common Commands

### Initial Setup
```bash
bin/setup          # Initial environment setup
bin/dev            # Start development server with all services
```

### Development
```bash
bin/rails server   # Start Rails server
bin/rails console  # Rails console
bin/jobs           # Start background job processor
```

### Database Management
```bash
bin/rails db:create                    # Create databases
bin/rails db:ridgepole:apply          # Apply schema changes
bin/rails db:seed                     # Load sample data
```

### Testing
```bash
bin/rspec                              # Run all tests
bin/rspec spec/models                 # Run model tests
bin/rspec spec/system                 # Run system tests
```

### Code Quality
```bash
bin/rubocop                            # Code style check
bin/rubocop -a                        # Auto-fix style issues
bin/brakeman                           # Security scan
```

### Asset Management
```bash
bin/rails assets:precompile           # Compile assets for production
bin/rails tailwindcss:build          # Build Tailwind CSS
```

## Build Process

- **Assets**: Propshaft for asset pipeline
- **CSS**: Tailwind CSS with automatic rebuilding on file changes
- **JavaScript**: ImportMap with Stimulus controllers
- **Components**: ViewComponent compilation
- **Database**: Ridgepole schema application

## Deployment

- **Docker**: Multi-stage Dockerfile for production builds
- **GitHub Actions**: Automated CI/CD pipeline
- **ECR**: Automatic Docker image deployment to AWS ECR
- **Health Checks**: Built-in `/up` endpoint for load balancers