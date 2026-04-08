# How to Fix API Quota Error

## The Problem
You've hit the free tier limits for Google's Gemini API:
- **15 requests per minute**
- **1,500 requests per day**
- **1 million tokens per day**

## Solutions (Choose One)

### ✅ Solution 1: Get a New Free API Key (Recommended)

This is the fastest solution:

1. **Use a different Google account** (or create a new one)
2. Go to: https://aistudio.google.com/apikey
3. Sign in with the new account
4. Click "Create API Key"
5. Copy the new key
6. Open `lib/config.dart` in your project
7. Replace the old key with the new one
8. Save and restart your app

**Why this works:** Each Google account gets its own free quota!

---

### ⏰ Solution 2: Wait for Quota Reset

- Free tier quota resets every 24 hours
- Wait until tomorrow and try again
- Your current key will work again after reset

---

### 💳 Solution 3: Enable Billing (For Production)

If you need higher limits:

1. Go to: https://console.cloud.google.com/
2. Select your project (or create one)
3. Enable billing
4. Link your Gemini API key to the project

**Paid tier limits:**
- 1,000 requests per minute
- Much higher daily limits
- Pay only for what you use (very cheap for testing)

---

## What I Added to Prevent This

### 1. Rate Limiting
- Scanner now enforces 5-second wait between scans
- Prevents accidental quota exhaustion
- Shows helpful message if you scan too quickly

### 2. Better Error Messages
- Clear explanation when quota is hit
- Shows all available solutions
- Displays quota limits

### 3. Improved Logging
- Debug console shows exact error
- Helps diagnose issues faster

---

## Quick Test

After getting a new API key, test it:

```bash
# Windows PowerShell
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_NEW_KEY"
```

If you see a list of models, it's working! ✅

---

## Tips to Avoid Quota Issues

1. **Don't spam the scanner** - Wait a few seconds between scans
2. **Use different accounts for testing** - Keep one for production
3. **Monitor your usage** at https://aistudio.google.com/
4. **Consider enabling billing** if building for real users

---

## Current Configuration

- Model: `gemini-2.0-flash` (fast and efficient)
- Endpoint: `v1beta` (supports latest models)
- Rate limit: 5 seconds between scans
- Error handling: Comprehensive with helpful messages
