# Convoy App Project Outline

## 1. Project Summary

**Working name:** Convoy App  
**Platform:** iOS first, with selected Apple CarPlay support  
**Audience:** Car enthusiasts, driving clubs, road trip groups, and friends who want to drive together safely.

The app helps drivers create or join a **convoy**: a temporary or ongoing driving group where members can see each other's live locations, communicate with the group, plan stops, and access useful driving information such as fuel prices.

The mobile app should contain the full feature set. The CarPlay experience must be limited to safe, glanceable, driving-focused features that comply with Apple's CarPlay rules and template restrictions.

---

## 2. Core Product Idea

The app is a social driving and convoy coordination tool.

Users should be able to:

- Create an account and profile.
- Add or invite friends.
- Create a convoy group.
- Join a convoy using an invite link, code, or friend invite.
- See convoy members on a live map.
- Share their own live location with the convoy.
- Communicate with the convoy using safe messaging or voice-first features.
- View useful driving information, such as nearby fuel prices.
- Plan meeting points, stops, routes, and destinations.
- Use a simplified CarPlay interface while driving.

---

## 3. Important CarPlay Notes

CarPlay is not a free-form second screen for any iOS app. It only supports approved app categories and system-defined templates. The app should treat CarPlay as a **driving-safe companion interface**, not as a full version of the mobile app.

Potentially relevant CarPlay categories for this product:

- **Navigation:** if the app provides route guidance or convoy route support.
- **Fueling:** if the app focuses on finding fuel stations and fuel-related actions.
- **Communication:** only if messaging or voice communication follows Apple's communication app requirements.
- **Driving task apps:** if the app supports simple driving-related tasks.
- **Live Activities / widgets:** useful for showing convoy status or next stop information without building every feature as a CarPlay app screen.

The project should confirm the exact CarPlay category and entitlement strategy early. Apple requires appropriate CarPlay entitlements before a CarPlay-enabled app can be distributed.

### CarPlay safety principle

Do not attempt to show the full social experience, long text chat, complex profile pages, image feeds, or distracting UI in CarPlay. Keep CarPlay screens short, glanceable, and action-focused.

---

## 4. MVP Scope

The MVP should prove the main convoy experience before adding advanced features.

### MVP Mobile App Features

#### Authentication

- Sign up.
- Log in.
- Log out.
- Basic profile setup.
- Username/display name.
- Optional profile photo.

#### Friends

- Search for users.
- Send friend requests.
- Accept or decline friend requests.
- View friends list.

#### Convoys

- Create a convoy.
- Set convoy name.
- Set optional destination.
- Generate invite code or invite link.
- Invite friends.
- Join convoy using code/link.
- Leave convoy.
- End convoy if owner/admin.

#### Live Location Map

- Show user's own location.
- Show convoy members on map.
- Update locations in near real time.
- Show member name and last updated time.
- Handle stale/offline users clearly.
- Allow user to stop sharing location.

#### Convoy Communication

For MVP, keep communication simple and safe:

- Text chat in the mobile app only.
- Push notifications for important convoy updates.
- Avoid text chat in CarPlay.

Possible later upgrade:

- Voice notes.
- Push-to-talk style audio rooms.
- Siri-driven messaging if CarPlay communication support is pursued.

#### Fuel Prices

- Show nearby fuel stations.
- Show fuel price where available.
- Use a GOV fuel price API or approved public data source.
- Allow filtering by fuel type, such as petrol, diesel, premium, or EV charging if added later.
- Show last updated timestamp for price data.

---

## 5. CarPlay MVP Scope

The first CarPlay version should be intentionally small.

Recommended CarPlay MVP:

- Show active convoy status.
- Show destination or next meeting point.
- Show distance/time to destination if navigation is supported.
- Show simple list of convoy members with safe status labels, such as:
  - Nearby
  - Behind
  - Ahead
  - Stopped
  - Offline
- Show nearby fuel stations if fueling category is approved.
- Start navigation to convoy destination or next stop if navigation support is approved.
- Provide simple voice-first actions where possible.

Avoid in CarPlay MVP:

- Free-form text chat.
- Social feeds.
- User profiles.
- Image uploads.
- Complex map interactions unless the app is approved as a navigation app.
- Anything that requires long reading or typing while driving.

---

## 6. Suggested Technical Architecture

### iOS App

Recommended stack:

- Swift.
- SwiftUI for standard iOS screens.
- MapKit or another approved map provider.
- Core Location for device location.
- Push notifications for convoy events.
- CarPlay framework for CarPlay screens.

### Backend

The backend should manage accounts, convoys, location updates, chat, and external data integrations.

Possible stack:

- REST API or GraphQL API.
- WebSocket service for live convoy updates.
- PostgreSQL for structured data.
- Redis for temporary live location/session state.
- Background jobs for fuel price updates.
- Object storage for profile images if needed.

### Real-Time Updates

Use WebSockets or a managed real-time service for:

- Live location updates.
- Convoy member join/leave events.
- Chat messages.
- Admin actions.

Location updates should be throttled to protect battery life and reduce backend load.

Example approach:

- Send location every 3-10 seconds during active convoy mode.
- Send less often when stationary.
- Stop updates when convoy ends or user disables sharing.
- Mark users as stale if no update is received for a set time.

---

## 7. Suggested Data Models

### User

- id
- display_name
- username
- email
- profile_photo_url
- created_at
- updated_at

### Friendship

- id
- requester_user_id
- recipient_user_id
- status: pending / accepted / blocked
- created_at
- updated_at

### Convoy

- id
- name
- owner_user_id
- status: active / ended
- destination_name
- destination_latitude
- destination_longitude
- invite_code
- created_at
- ended_at

### ConvoyMember

- id
- convoy_id
- user_id
- role: owner / admin / member
- status: active / left / removed
- joined_at
- left_at

### LocationUpdate

This may be stored short-term rather than permanently.

- id
- convoy_id
- user_id
- latitude
- longitude
- speed
- heading
- accuracy
- recorded_at

### ChatMessage

- id
- convoy_id
- sender_user_id
- message
- created_at
- deleted_at

### FuelStation

- id
- external_id
- brand
- name
- address
- latitude
- longitude
- fuel_types
- last_updated_at

### FuelPrice

- id
- station_id
- fuel_type
- price
- currency
- last_updated_at
- source

---

## 8. Key User Flows

### Create a Convoy

1. User opens app.
2. User taps Create Convoy.
3. User enters convoy name.
4. User optionally adds destination or meeting point.
5. App creates convoy.
6. App generates invite code/link.
7. User invites friends.
8. Live map opens.

### Join a Convoy

1. User receives invite link or code.
2. User opens app.
3. User joins convoy.
4. App asks for location permission if not already granted.
5. User appears on convoy map.
6. Other members are notified.

### Active Convoy

1. Members drive together.
2. App updates member locations.
3. Map shows member positions.
4. App highlights if someone stops, drops behind, or goes offline.
5. Members can view next stop or destination.
6. Convoy owner can end the convoy.

### Find Fuel

1. User opens fuel screen.
2. App gets user's location or convoy route area.
3. App fetches nearby stations.
4. User filters by fuel type.
5. App displays prices and last updated time.
6. User can navigate to selected station.

---

## 9. Permissions and Privacy

Location sharing is the most sensitive part of the app. The app must be clear and trustworthy.

Required privacy behaviour:

- Ask for location permission only when needed.
- Explain why location is needed.
- Allow users to stop sharing location at any time.
- Only share location with active convoy members.
- Make it obvious when live sharing is active.
- Stop location sharing when the user leaves or ends a convoy.
- Avoid storing detailed location history unless there is a clear reason.
- If location history is stored, provide retention rules and deletion options.

Suggested privacy defaults:

- Live location is only active inside an active convoy.
- Last known location expires after a short time.
- Ended convoys do not continue tracking members.

---

## 10. Safety Requirements

Because the app is used while driving, safety should be treated as a core requirement.

- Do not encourage phone interaction while driving.
- Keep driving mode UI simple.
- Prefer voice, glanceable information, and passenger-safe interactions.
- Lock or simplify complex features during active driving.
- Avoid typing-heavy features in driving contexts.
- Add clear warnings where appropriate.
- CarPlay must only use approved templates and driving-safe flows.

---

## 11. Suggested Screens

### Mobile App Screens

- Welcome / login.
- Sign up.
- Profile setup.
- Home dashboard.
- Friends list.
- Add friends.
- Convoy list.
- Create convoy.
- Join convoy.
- Active convoy map.
- Convoy chat.
- Convoy members.
- Fuel prices map/list.
- Settings.
- Privacy/location settings.

### CarPlay Screens

- Active convoy overview.
- Convoy members status list.
- Destination / next stop.
- Nearby fuel stations.
- Navigation action screen, if navigation entitlement is approved.

---

## 12. API Requirements

### Auth API

- POST /auth/register
- POST /auth/login
- POST /auth/logout
- GET /me
- PATCH /me

### Friends API

- GET /friends
- POST /friends/requests
- POST /friends/requests/{id}/accept
- POST /friends/requests/{id}/decline
- DELETE /friends/{id}

### Convoy API

- POST /convoys
- GET /convoys
- GET /convoys/{id}
- POST /convoys/{id}/join
- POST /convoys/join-by-code
- POST /convoys/{id}/leave
- POST /convoys/{id}/end

### Location API

- POST /convoys/{id}/location
- GET /convoys/{id}/locations

For live updates, prefer WebSockets instead of polling.

### Chat API

- GET /convoys/{id}/messages
- POST /convoys/{id}/messages

### Fuel API

- GET /fuel/stations/nearby
- GET /fuel/stations/{id}
- GET /fuel/prices

---

## 13. WebSocket Events

Suggested events:

### Client to Server

- convoy:join
- convoy:leave
- location:update
- chat:message
- convoy:end

### Server to Client

- member:joined
- member:left
- member:location_updated
- member:stale
- chat:message_created
- convoy:ended
- fuel:station_suggestion

---

## 14. Admin and Moderation

Convoys can involve multiple users, so moderation should be considered early.

MVP admin features:

- Convoy owner can remove a member.
- Convoy owner can end the convoy.
- Users can block other users.
- Users can report abusive behaviour.

Future moderation features:

- Club/group admins.
- Permanent car clubs.
- Event pages.
- Public/private convoy discovery.
- Rate limits for spam prevention.

---

## 15. Future Feature Ideas

- Permanent clubs/groups.
- Public car meets.
- Event planning.
- Route planning.
- Suggested scenic driving routes.
- Push-to-talk voice channels.
- SOS or breakdown alert to convoy.
- Dashcam/photo sharing after convoy ends.
- Vehicle profiles.
- Badges or achievements.
- Weather alerts.
- Speed camera or road hazard warnings, subject to legal review.
- EV charging support.
- Apple Watch companion app.
- Live Activity for active convoy status.
- Widgets for next convoy or active convoy status.

---

## 16. Development Phases

### Phase 1: Planning and Validation

- Confirm exact MVP.
- Confirm CarPlay category strategy.
- Confirm fuel price data source.
- Create wireframes.
- Define backend architecture.
- Define privacy policy approach.

### Phase 2: Core iOS App

- Build authentication.
- Build profiles.
- Build friends system.
- Build create/join convoy.
- Build active convoy map.
- Build basic backend APIs.

### Phase 3: Real-Time Convoy Mode

- Add WebSockets.
- Add live location updates.
- Add stale/offline states.
- Add convoy member status.
- Add push notifications.

### Phase 4: Fuel Prices

- Integrate fuel price API.
- Store/cache station data.
- Show nearby stations.
- Add filters.
- Add navigation handoff.

### Phase 5: CarPlay Prototype

- Request/confirm correct CarPlay entitlement.
- Add CarPlay scene.
- Build simple convoy overview template.
- Build safe member status list.
- Build fuel station list if allowed.
- Test with CarPlay Simulator.

### Phase 6: Polish and Release Prep

- Improve UI.
- Add error handling.
- Add analytics.
- Add crash reporting.
- Add privacy policy.
- Add App Store assets.
- Test battery usage.
- Test location permission flows.
- Test poor network handling.

---

## 17. Technical Risks

### CarPlay Approval Risk

Apple may reject or limit features that do not fit approved CarPlay categories. The app should not depend on full CarPlay functionality for MVP success.

### Battery Drain

Live GPS updates can drain battery. Use adaptive update frequency and stop tracking when not needed.

### Privacy Concerns

Users may be cautious about live location sharing. Make controls clear and transparent.

### Real-Time Scaling

Live convoys require reliable real-time infrastructure. Avoid inefficient polling for active map updates.

### Fuel API Reliability

Fuel price data may be incomplete, delayed, or inconsistent. Always show last updated time and handle missing prices.

---

## 18. Agent Instructions

When working on this project, prioritise the following:

1. Build the iOS mobile MVP first.
2. Keep code simple, maintainable, and well commented.
3. Do not overbuild social features before convoy/location features work.
4. Treat CarPlay as a limited, safety-first extension.
5. Confirm CarPlay entitlement/category assumptions before implementing CarPlay-heavy features.
6. Design location sharing with privacy controls from the start.
7. Prefer clear APIs and simple data models.
8. Use real-time updates for active convoy location sharing.
9. Keep fuel price integration isolated behind a service layer so the data source can change later.
10. Make the project easy to test locally.

---

## 19. Definition of Done for MVP

The MVP is complete when:

- A user can sign up and log in.
- A user can add friends.
- A user can create a convoy.
- Friends can join the convoy.
- Members can see each other's live locations on a map.
- Members can leave the convoy.
- The owner can end the convoy.
- Users can stop sharing location.
- Nearby fuel prices can be viewed where data is available.
- Basic convoy chat works in the mobile app.
- The app handles poor signal, stale locations, and offline users gracefully.
- A small CarPlay prototype shows safe convoy information if entitlement/category approval allows it.

---

## 20. Open Questions

The agent should help answer or clarify these during development:

- What is the exact app name?
- Will the app use Apple-only sign in, email/password, or social login?
- Which map provider should be used?
- Which GOV fuel price API will be used and what are its limits?
- Should convoys be temporary only, or can users create permanent clubs?
- Should users be able to join public convoys?
- Should live location history be stored after a convoy ends?
- What CarPlay category is the best fit?
- Is turn-by-turn navigation required, or can the app hand off to Apple Maps/Google Maps?
- Should voice chat be part of MVP or a later phase?
