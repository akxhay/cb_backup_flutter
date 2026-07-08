# Facebook Audience Network Proguard Rules
-keep class com.facebook.ads.** { *; }
-dontwarn com.facebook.ads.internal.**
-dontwarn com.facebook.infer.annotation.Nullsafe
