# Car Convoy Manager App - Implementation Plan

## Overview

Build a modern iOS app for managing car convoys with push-to-talk, real-time minimap tracking of friends' locations, and convoy coordination. Three-phase approach: authentication → profile onboarding → blank main interface ready for convoy features.

**Tech Stack:**
- **Frontend:** SwiftUI (iOS 16+), Keychain for secure token storage
- **Backend:** Node.js/Express (or Python choice), PostgreSQL, Redis, MinIO/S3-compatible storage
- **Authentication:** OAuth 2.0 (Sign in with Apple, Google, Facebook) + Email with verification
- **Hosting:** User's VPS for all backend services

---

## Phase 1: VPS Backend Infrastructure Setup

### 1.1 Server Requirements

**Tech Stack Choice** (decide on one):
- Option A: Node.js + Express (recommended for simplicity)
- Option B: Python + FastAPI/Django
- Option C: Go + Gin

**Core Services Needed:**
1. **API Server** — REST or GraphQL endpoints for auth, user profiles, convoy management
2. **PostgreSQL Database** — User accounts, profiles, convoy memberships, locations history
3. **Redis** — Session management, token refresh, rate limiting
4. **Email Service** — SendGrid/Mailgun for verification emails and OTP codes
5. **File Storage** — MinIO (S3-compatible) on VPS for profile pictures
6. **JWT Auth** — Token generation, validation, refresh flow

### 1.2 Database Schema (PostgreSQL)

```
users
  - id (UUID, PK)
  - email (unique)
  - email_verified_at
  - password_hash (nullable if OAuth)
  - oauth_provider (google/facebook/apple)
  - oauth_id
  - created_at
  - updated_at

profiles
  - id (UUID, PK)
  - user_id (FK → users)
  - username (unique)
  - display_name
  - profile_picture_url
  - bio (nullable)
  - car_make (nullable)
  - car_model (nullable)
  - car_color (nullable)
  - car_plate (nullable)
  - created_at
  - updated_at

email_verifications
  - id (UUID, PK)
  - user_id (FK → users)
  - otp_code
  - expires_at
  - verified_at (nullable)

convoys
  - id (UUID, PK)
  - created_by (FK → users)
  - name
  - created_at
  - disbanded_at (nullable)

convoy_members
  - id (UUID, PK)
  - convoy_id (FK → convoys)
  - user_id (FK → users)
  - joined_at
  - left_at (nullable)

locations
  - id (UUID, PK)
  - user_id (FK → users)
  - latitude
  - longitude
  - timestamp
  - convoy_id (FK → convoys, nullable)
```

### 1.3 API Endpoints (to be implemented)

**Auth:**
- `POST /auth/register` — Email signup
- `POST /auth/email/verify-otp` — Verify email with OTP
- `POST /auth/oauth/initiate` — Start OAuth flow
- `POST /auth/oauth/callback` — Handle OAuth callback
- `POST /auth/login` — Email/password login
- `POST /auth/refresh-token` — Refresh JWT
- `POST /auth/logout` — Invalidate token

**Profiles:**
- `GET /api/profiles/me` — Get authenticated user's profile
- `POST /api/profiles/create` — Create initial profile (username, display name, etc.)
- `PATCH /api/profiles/me` — Update profile info
- `POST /api/profiles/me/picture` — Upload profile picture
- `GET /api/profiles/:username` — Get public profile by username

**Convoys:**
- `POST /api/convoys` — Create new convoy
- `GET /api/convoys/active` — List user's active convoys
- `POST /api/convoys/:convoyId/join` — Join convoy
- `POST /api/convoys/:convoyId/leave` — Leave convoy

**Locations:**
- `POST /api/locations/update` — Submit current location
- `GET /api/convoys/:convoyId/locations` — Get all members' live locations in convoy

### 1.4 VPS Deployment Checklist

- [ ] Install Node.js/npm (or Python + pip)
- [ ] Install PostgreSQL and configure database
- [ ] Install Redis
- [ ] Set up MinIO for S3-compatible file storage
- [ ] Configure reverse proxy (Nginx) and SSL certificates (Let's Encrypt)
- [ ] Set up email service account (SendGrid/Mailgun API key)
- [ ] Create `.env` file with secrets (DB connection, API keys, JWT secret, etc.)
- [ ] Deploy API server
- [ ] Set up automated backups for PostgreSQL
- [ ] Configure firewall rules (expose only ports 443/80 for HTTPS)
- [ ] Document all credentials and connection strings securely

---

## Phase 2: iOS Authentication & Profile Onboarding

### 2.1 Navigation Flow

```
App Launch
  ↓
AuthenticationView (check if logged in)
  ├─→ User has valid token → MainInterfaceView
  └─→ User logged out → LoginSignupView
        ├─→ Email signup → EmailSignupView
        │     ├─→ Enter email + password
        │     ├─→ Send OTP to email
        │     └─→ VerifyEmailView (enter OTP)
        │           └─→ On success → ProfileSetupView
        │
        ├─→ Sign in with Apple → (OAuth callback) → ProfileSetupView (if new user)
        │
        ├─→ Sign in with Google → (OAuth callback) → ProfileSetupView (if new user)
        │
        └─→ Sign in with Facebook → (OAuth callback) → ProfileSetupView (if new user)

ProfileSetupView (onboarding wizard)
  ├─→ Step 1: Choose Username
  │     ├─→ Input field with real-time availability check
  │     └─→ "Username taken" / "Available" feedback
  │
  ├─→ Step 2: Display Name & Bio
  │     ├─→ Input for informal display name
  │     └─→ Optional bio/about section
  │
  ├─→ Step 3: Profile Picture
  │     ├─→ Photo picker (camera or library)
  │     └─→ Crop/resize UI
  │
  ├─→ Step 4: Car Info (Optional)
  │     ├─→ Car make (dropdown or text)
  │     ├─→ Car model (dropdown or text)
  │     ├─→ Car color (optional)
  │     └─→ License plate (optional)
  │
  └─→ "Complete Setup" button
        └─→ POST all data to backend
              └─→ MainInterfaceView

MainInterfaceView (blank for now)
  ├─→ Tab bar (or side menu) with placeholders
  └─→ Ready for: Convoy list, Live map, PTT control, etc.
```

### 2.2 Authentication Implementation Details

**State Management:**
```swift
@MainActor
class AuthenticationManager: ObservableObject {
  @Published var isLoggedIn: Bool
  @Published var currentUser: UserProfile?
  @Published var authToken: String? // stored in Keychain
  @Published var refreshToken: String? // stored in Keychain
  @Published var isLoading: Bool = false
  @Published var error: String?
  
  // Methods
  func signUpWithEmail(_ email: String, _ password: String) async throws
  func verifyEmailWithOTP(_ otp: String) async throws
  func signInWithApple() async throws
  func signInWithGoogle() async throws
  func signInWithFacebook() async throws
  func refreshAccessToken() async throws
  func logout()
  func restoreSession() // called on app launch
}
```

**Keychain Storage:**
- Use `SecureStore` utility to save/retrieve auth tokens
- Never store sensitive data in UserDefaults
- Implement token refresh logic (on 401 response)

**Email Verification Flow:**
1. User enters email + password → POST `/auth/register`
2. Backend generates OTP and sends via email (6-digit, 15 min expiry)
3. User enters OTP in app → POST `/auth/email/verify-otp`
4. Backend validates OTP, creates user account
5. Backend returns JWT token + refresh token
6. App stores tokens in Keychain, proceeds to ProfileSetupView

**OAuth Flow (Sign in with Apple):**
1. User taps "Sign in with Apple" button
2. iOS presents Apple login sheet
3. App receives `identityToken` and `userIdentifier`
4. App sends token to backend → POST `/auth/oauth/callback?provider=apple&token=...`
5. Backend validates token against Apple's servers
6. Backend checks if user exists:
   - If yes: return JWT
   - If no: create temporary session, redirect to ProfileSetupView
7. App stores JWT, proceeds to profile setup or main interface

**Google/Facebook OAuth** — Similar flow but via Firebase Auth or custom OAuth handlers.

### 2.3 Profile Onboarding Screens

**Screen 1: Username Selection**
- Text input with debounced API call to check availability
- Real-time validation: "✓ Available" or "✗ Taken"
- Minimum 3 chars, alphanumeric + underscore only
- "Next" button (enabled when valid, unique username chosen)

**Screen 2: Display Name & Bio**
- Text field: Display Name (required, 2-50 chars)
- Text view: Bio (optional, 0-500 chars)
- Show character count for bio
- "Next" button

**Screen 3: Profile Picture**
- Circular avatar placeholder with camera icon
- Tap to show action sheet: "Take Photo" / "Choose from Library" / "Skip"
- If selected: crop/scale interface (square crop)
- Show preview of selected image
- "Next" button

**Screen 4: Car Info (Optional)**
- "Add your car (optional)" section
- Dropdowns/text fields for:
  - Make (e.g., Tesla, BMW, Honda)
  - Model (e.g., Model 3, M340i)
  - Color (optional)
  - License Plate (optional)
- "Skip" button (allows skipping entirely)
- "Complete Setup" button

**Design Notes:**
- Modern, clean UI using SwiftUI's latest features
- Use SF Symbols for icons
- Consistent spacing (16pt margins, 12pt padding)
- Progress indicator at top (e.g., "Step 2 of 4")
- Smooth transitions between steps
- Form validation with inline error messages

### 2.4 Login Variants

**Option A: Email/Password**
```
LoginSignupView
  ├─→ Email input
  ├─→ Password input (masked)
  ├─→ "Sign Up" button → EmailSignupView
  └─→ "Log In" button → POST /auth/login
```

**Option B: Social-Only (Optional)**
- Show only "Sign in with Apple/Google/Facebook" buttons
- No email/password option
- Simpler UX, relies on OAuth providers entirely

---

## Phase 3: Main Interface & Navigation Structure

### 3.1 Main Interface Skeleton (Blank for Now)

```swift
struct MainInterfaceView: View {
  enum Tab {
    case convoy
    case map
    case settings
  }
  
  @State var selectedTab: Tab = .convoy
  
  var body: some View {
    TabView(selection: $selectedTab) {
      // Tab 1: Convoy List (blank for now)
      ConvoyListView()
        .tabItem {
          Label("Convoy", systemImage: "car.2")
        }
        .tag(Tab.convoy)
      
      // Tab 2: Live Map (blank for now)
      LiveMapView()
        .tabItem {
          Label("Map", systemImage: "map")
        }
        .tag(Tab.map)
      
      // Tab 3: Settings (blank for now)
      SettingsView()
        .tabItem {
          Label("Settings", systemImage: "gear")
        }
        .tag(Tab.settings)
    }
    // PTT (Push-to-Talk) button floating at bottom
    .overlay(alignment: .bottomTrailing) {
      PushToTalkButton()
        .padding(20)
    }
  }
}

// Placeholder views
struct ConvoyListView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Your Convoys")
        .font(.title2)
        .fontWeight(.bold)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(16)
  }
}

struct LiveMapView: View {
  var body: some View {
    VStack {
      Text("Live Map - Coming Soon")
        .font(.title2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct SettingsView: View {
  var body: some View {
    VStack {
      Text("Settings - Coming Soon")
        .font(.title2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct PushToTalkButton: View {
  var body: some View {
    Button(action: {}) {
      Image(systemName: "mic.circle.fill")
        .font(.system(size: 60))
        .foregroundColor(.blue)
    }
  }
}
```

### 3.2 App Root Structure

```swift
@main
struct CarConvoyApp: App {
  @StateObject var authManager = AuthenticationManager()
  
  var body: some Scene {
    WindowGroup {
      if authManager.isLoggedIn {
        if authManager.currentUser?.profileCompleted == true {
          MainInterfaceView()
        } else {
          ProfileSetupView()
        }
      } else {
        AuthenticationView()
      }
    }
    .onAppear {
      Task {
        await authManager.restoreSession()
      }
    }
  }
}
```

---

## Phase 4: API Integration Layer

### 4.1 Networking Service

```swift
struct APIRequest {
  let method: String // GET, POST, PATCH, etc.
  let endpoint: String
  let body: Encodable?
  let requiresAuth: Bool
}

class APIService {
  static let shared = APIService()
  
  private let baseURL: URL // from config/environment
  @Injected var authManager: AuthenticationManager
  
  func request<T: Decodable>(_ req: APIRequest) async throws -> T {
    // 1. Build URL
    // 2. Add headers (including Authorization if needed)
    // 3. Encode body if present
    // 4. Execute request
    // 5. Handle 401 → refresh token → retry
    // 6. Decode response or throw error
  }
  
  func upload<T: Decodable>(
    _ req: APIRequest,
    fileData: Data,
    fileName: String
  ) async throws -> T {
    // Multipart form data upload for profile pictures
  }
}
```

### 4.2 Request/Response Models

```swift
// Auth
struct SignUpRequest: Codable {
  let email: String
  let password: String
}

struct SignUpResponse: Codable {
  let userId: String
  let requiresEmailVerification: Bool
}

struct OTPVerificationRequest: Codable {
  let userId: String
  let otpCode: String
}

struct AuthTokenResponse: Codable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Int
}

// Profiles
struct ProfileSetupRequest: Codable {
  let username: String
  let displayName: String
  let bio: String?
  let carMake: String?
  let carModel: String?
  let carColor: String?
  let carPlate: String?
}

struct UserProfile: Codable, Identifiable {
  let id: String
  let email: String
  let username: String
  let displayName: String
  let profilePictureUrl: String?
  let bio: String?
  let profileCompleted: Bool
  
  // Car info
  let carMake: String?
  let carModel: String?
  let carColor: String?
  let carPlate: String?
}
```

---

## Implementation Checklist

### Backend (VPS)

- [ ] Install and configure PostgreSQL, Redis, MinIO
- [ ] Set up Node.js server with Express
- [ ] Create database schema and migrations
- [ ] Implement auth endpoints (signup, verify OTP, OAuth callbacks, login, refresh)
- [ ] Implement profile endpoints (create, update, upload picture)
- [ ] Implement username availability check
- [ ] Set up email service integration (SendGrid/Mailgun)
- [ ] Implement JWT token generation and validation
- [ ] Set up CORS for iOS app
- [ ] Deploy to VPS with SSL/TLS
- [ ] Document all API endpoints with request/response examples
- [ ] Set up logging and monitoring

### iOS Frontend

- [ ] Create `AuthenticationManager` with state management
- [ ] Implement `SecureStore` utility for Keychain access
- [ ] Create `AuthenticationView` (routing logic)
- [ ] Build `LoginSignupView` (email + social login buttons)
- [ ] Build `EmailSignupView` (email + password input)
- [ ] Build `VerifyEmailView` (OTP entry)
- [ ] Implement `ProfileSetupView` (4-step wizard)
  - [ ] Step 1: Username selection with availability check
  - [ ] Step 2: Display name & bio
  - [ ] Step 3: Profile photo picker
  - [ ] Step 4: Car info (optional)
- [ ] Create `APIService` for networking with token refresh
- [ ] Build `MainInterfaceView` with tab navigation
  - [ ] Blank ConvoyListView
  - [ ] Blank LiveMapView
  - [ ] Blank SettingsView
  - [ ] Floating PTT button (stub)
- [ ] Implement Sign in with Apple integration
- [ ] Integrate Google OAuth (via Firebase or custom)
- [ ] Integrate Facebook OAuth (via Firebase or custom)
- [ ] Test end-to-end auth flow
- [ ] Test profile creation flow
- [ ] Test session restoration on app relaunch
- [ ] Apply modern, clean UI design across all screens

### Testing & Deployment

- [ ] Test email signup flow end-to-end
- [ ] Test each OAuth provider
- [ ] Test OTP verification
- [ ] Test token refresh and expiry
- [ ] Test profile photo upload and storage
- [ ] Test username availability checking
- [ ] Test graceful error handling and user feedback
- [ ] Verify Keychain storage is secure
- [ ] Test app restart with valid token (session restoration)
- [ ] Test logout and token invalidation
- [ ] Load testing on backend
- [ ] Set up staging and production API endpoints
- [ ] Create build variants for staging/prod in Xcode

---

## VPS Setup Guide (Summary)

### Quick Start Commands

```bash
# On your VPS:

# 1. Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 2. Install PostgreSQL
sudo apt-get install -y postgresql postgresql-contrib

# 3. Install Redis
sudo apt-get install -y redis-server

# 4. Install MinIO (S3-compatible storage)
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
./minio server /data

# 5. Set up Nginx reverse proxy
sudo apt-get install -y nginx
# Configure /etc/nginx/sites-available/default to forward to :3000

# 6. Get SSL cert (Let's Encrypt)
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot certonly --nginx -d yourdomain.com

# 7. Create .env file with secrets
# DATABASE_URL=postgresql://user:pass@localhost:5432/convoy_db
# JWT_SECRET=<random_long_string>
# SENDGRID_API_KEY=<your_key>
# MINIO_ENDPOINT=localhost:9000
# MINIO_ACCESS_KEY=minioadmin
# MINIO_SECRET_KEY=minioadmin

# 8. Deploy and start
npm install && npm start
```

### Secrets to Protect

- PostgreSQL credentials
- JWT secret key
- SendGrid/Mailgun API key
- MinIO access/secret keys
- OAuth provider IDs and secrets
- Database connection string

**Use environment variables, never hardcode!**

---

## Design System (iOS)

### Color Palette
- **Primary:** Blue (#007AFF or system blue)
- **Secondary:** Gray (#5AC8FA or system gray)
- **Background:** White or light gray (#F8F8F8)
- **Accent:** Green for success, Red for error
- **Text:** Dark gray (#333333) on light backgrounds

### Typography
- **Headlines:** SF Pro Display, Bold, 32pt
- **Subheadings:** SF Pro Display, Semibold, 20pt
- **Body:** SF Pro Text, Regular, 16pt
- **Captions:** SF Pro Text, Regular, 12pt

### Spacing
- Standard margin/padding: 16pt
- Form elements: 12pt between fields
- Section dividers: 8pt
- Button height: 44pt (minimum for touch targets)

### Components
- Use system buttons and controls where possible
- Rounded corners: 12pt for cards, 8pt for smaller elements
- Shadows: Subtle (opacity 0.1, blur 4pt)
- Icons: SF Symbols only for consistency

---

## Next Steps

1. **Confirm security preferences:**
   - Email OTP or email link for verification?
   - Firebase Auth or custom JWT?
   - Managed OAuth (Firebase) or custom handlers?

2. **Decide on backend tech:**
   - Node.js + Express (recommended)
   - Python + FastAPI
   - Go + Gin
   - Other?

3. **Choose profile photo storage:**
   - MinIO on VPS (recommended for full control)
   - AWS S3 (external, easier management)
   - Cloudinary (CDN, simpler)

4. **Confirm social login priorities:**
   - Sign in with Apple (built-in, required)
   - Google (Firebase or custom)
   - Facebook (Firebase or custom)
   - Allow email-only signup?

5. **Review and finalize design system** with mockups

---

## Questions for Ben

1. **Backend preference:** Node.js/Express, Python, Go, or other?
2. **Social logins:** Prioritize which ones? Email-only fallback needed?
3. **Email verification:** OTP or magic link?
4. **Auth architecture:** Firebase Auth or custom JWT with VPS?
5. **Profile picture storage:** MinIO on VPS or external service?
6. **App deployment:** Testflight first, or direct App Store?
7. **Privacy/data:** GDPR compliance needed? Data residency requirements?
