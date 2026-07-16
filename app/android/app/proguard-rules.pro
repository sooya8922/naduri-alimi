# flutter_local_notifications: GSON 리플렉션 사용 → R8이 지우면 시작 크래시.
# (지금은 minify off라 미적용이지만, 스토어 빌드에서 축소를 켤 때를 대비해 동봉)
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# workmanager 백그라운드 콜백
-keep class be.tramckrijte.workmanager.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
