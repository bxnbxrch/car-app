# Car Convoy Manager App - Implementation Plan

## Overview

Build a modern iOS app for managing car convoys with push-to-talk, real-time minimap tracking of friends' locations, and convoy coordination. Three-phase approach: authentication → profile onboarding → blank main interface ready for convoy features.

**Confirmed Tech Stack:**
- **Frontend:** SwiftUI (iOS 16+), Keychain for secure token storage
- **Backend:** Node.js + Express, PostgreSQL, Redis
- **Authentication:** Firebase Auth (free tier) — Google OAuth + Email/OTP verification
- **File Storage:** Simple uploads to Node.js server (keep files small on disk)
- **Hosting:** VPS for Node.js API & PostgreSQL; Firebase Auth (Google-hosted, free)

---

## Phase 1: VPS Backend Infrastructure Setup

### 1.1 Server Requirements

**Confirmed: Node.js + Express**

**Core Services Needed:**
1. **Node.js API Server** — Express.js endpoints for user profiles, convoys, locations
2. **PostgreSQL Database** — Profiles, convoy memberships, locations (Firebase Auth manages user accounts separately)
3. **Redis** — Session management, rate limiting
4. **Firebase Auth** (free tier) — Google & Facebook OAuth, email/OTP verification, token management (no backend auth code needed)
5. **File Storage** — Simple file upload endpoint on Node.js server (store in `/uploads`, keep small <5MB per image)

### 1.2 Database Schema (PostgreSQL)

**Note:** Firebase Auth manages user accounts & authentication separately. Your VPS database stores only app data (profiles, convoys, locations). No password hashes or auth tokens in your DB.

```
profiles
  - id (UUID, PK)
  - firebase_uid (unique, links to Firebase Auth user)
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

### 1.3 API Endpoints (Your Node.js Server)

**Auth (Handled by Firebase — No custom auth endpoints needed):**
- Firebase SDK on iOS handles: email/password signup, OTP verification, Google & Facebook OAuth
- Your Node.js does NOT implement auth; Firebase is your auth provider

**Profiles (Your custom Node.js endpoints):**
- `POST /api/profiles/create` — Create initial profile (username, display name, photo, car info). Requires Firebase ID token in `Authorization: Bearer <idToken>` header
- `GET /api/profiles/me` — Get authenticated user's profile
- `PATCH /api/profiles/me` — Update profile info
- `POST /api/profiles/me/picture` — Upload profile picture (multipart/form-data, max 5MB). Stores in `/uploads` directory
- `GET /api/profiles/:username` — Get public profile by username
- `POST /api/profiles/check-username` — Check if username is available (used during onboarding)

**Convoys (Your custom Node.js endpoints):**
- `POST /api/convoys` — Create new convoy
- `GET /api/convoys/active` — List user's active convoys
- `POST /api/convoys/:convoyId/join` — Join convoy
- `POST /api/convoys/:convoyId/leave` — Leave convoy

**Locations (Your custom Node.js endpoints):**
- `POST /api/locations/update` — Submit current location
- `GET /api/convoys/:convoyId/locations` — Get all members' live locations in convoy

**Authentication on All Endpoints:**
All requests to `/api/*` require Firebase ID token in header: `Authorization: Bearer <idToken>`. 
Your Node.js middleware verifies token using Firebase Admin SDK (validates signature, checks expiry). If invalid, return 401.
No JWT refresh flow needed—Firebase handles tokens transparently on iOS (refresh happens in SDK).

### 1.4 VPS Deployment Checklist

- [ ] Install Node.js/npm
- [ ] Install PostgreSQL and configure database
- [ ] Install Redis
- [ ] Configure reverse proxy (Nginx) and SSL certificates (Let's Encrypt)
- [ ] Create Firebase project at console.firebase.google.com (completely free tier) ✓ DONE
- [ ] Enable Google OAuth in Firebase Console ✓ DONE
- [ ] Enable Email/Password + OTP in Firebase Console ✓ DONE
- [ ] Download Firebase Admin SDK service account key (JSON file)
- [ ] Create `.env` file with secrets:
  ```
  DATABASE_URL=postgresql://user:pass@localhost:5432/convoy_db
  FIREBASE_PROJECT_ID=your-firebase-project-id
  FIREBASE_PRIVATE_KEY=<from service account key JSON>
  FIREBASE_CLIENT_EMAIL=<from service account key JSON>
  REDIS_URL=redis://localhost:6379
  NODE_ENV=production
  ```
- [ ] Deploy Node.js API server
- [ ] Set up automated backups for PostgreSQL
- [ ] Configure firewall rules (expose only ports 443/80 for HTTPS)
- [ ] Create `/uploads` directory with proper permissions for profile pictures
- [ ] Document all credentials securely (Firebase keys, DB connection string)

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

## Appendix: Firebase Auth & TestFlight Notes

### Firebase Auth — Free Tier Details

**Cost:** 100% FREE for:
- Email/password authentication (unlimited)
- OAuth (Google, Facebook, etc.) — unlimited
- OTP verification — unlimited
- Up to 50,000 unique users per month in free tier

**After 50k users:** Still very cheap (~$0.005 per verification). Unlikely to hit costs at app launch.

**Setup:**
1. Go to https://console.firebase.google.com
2. Create new project (free)
3. Enable "Authentication" service
4. Add Google as sign-in provider (uses your Google account)
5. Add Facebook as sign-in provider (requires Facebook Developer account, also free)
6. Under iOS settings, add your app's bundle ID (`jh.car-app` or what you choose)
7. Download GoogleService-Info.plist and add to Xcode

**On iOS Side:**
- Use FirebaseAuth SDK (installed via CocoaPods)
- Handle email signup with OTP via `Auth.auth().createUser(withEmail:password:)`
- Firebase SDK automatically sends OTP emails
- No custom backend code for auth—Firebase is the auth server

---

### TestFlight Explained

**TestFlight** is Apple's free beta testing platform. Instead of going directly to App Store:

1. **Local Testing:** Build and run on your iPhone via Xcode (for development)
2. **TestFlight Beta:** Upload build to TestFlight, distribute to test users (family, friends) via TestFlight app
3. **Public Beta:** Optional—allow anyone with a link to test
4. **App Store Release:** Submit to App Store for review (7-14 days typically)

**Timeline for your app:**
- Phase 1-2-3 complete (auth, profile, main interface) → Build and test locally in Xcode simulator
- Ready to show family/friends → Push to TestFlight
- Minor fixes → TestFlight beta 2, 3, etc.
- Polished & ready → Submit to App Store

**Recommended approach:** TestFlight first (before App Store) to iron out bugs with real users on real hardware.

---

## Tech Debt & Future Improvements

- [ ] Implement push notifications for convoy invites (APNs setup)
- [ ] Add real convoy map (MapKit, display friend locations)
- [ ] Implement PTT (WebRTC, Twilio, Agora)
- [ ] Add convoy messaging/chat
- [ ] Caching strategy for locations (reduce API calls)
- [ ] Offline support (sync when reconnected)
