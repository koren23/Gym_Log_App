package com.korengym.gym_tracker

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class GymWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (widgetId in appWidgetIds) {
      updateAppWidget(context, appWidgetManager, widgetId, widgetData)
    }
  }

  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: android.os.Bundle,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    updateAppWidget(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
  }

  private enum class Tier { COMPACT, MEDIUM, LARGE, XLARGE }

  companion object {
    private const val TIER_MEDIUM_MIN_HEIGHT_DP = 110
    private const val TIER_LARGE_MIN_HEIGHT_DP = 180
    private const val TIER_XLARGE_MIN_HEIGHT_DP = 240

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
    ) {
      val streakWeeks = widgetData.getInt("streak_weeks", 0)
      val bestStreakWeeks = widgetData.getInt("best_streak_weeks", 0)
      val bestStreakEnded = widgetData.getString("best_streak_ended", "") ?: ""

      fun color(key: String, fallbackRes: Int): Int =
          widgetData.getInt(key, context.getColor(fallbackRes))

      val bg = color("w_bg", R.color.widget_background)
      val surface = color("w_surface", R.color.widget_surface)
      val text = color("w_text", R.color.widget_text_dark)
      val textMuted = color("w_text_muted", R.color.widget_text_muted)
      val accent = color("w_accent", R.color.widget_hero)
      val button = color("w_button", R.color.widget_hero)
      val button2 = color("w_button2", R.color.widget_dashboard)

      val minHeightDp =
          appWidgetManager.getAppWidgetOptions(appWidgetId)
              .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, TIER_MEDIUM_MIN_HEIGHT_DP)

      val tier =
          when {
            minHeightDp >= TIER_XLARGE_MIN_HEIGHT_DP -> Tier.XLARGE
            minHeightDp >= TIER_LARGE_MIN_HEIGHT_DP -> Tier.LARGE
            minHeightDp >= TIER_MEDIUM_MIN_HEIGHT_DP -> Tier.MEDIUM
            else -> Tier.COMPACT
          }
      val layoutRes =
          when (tier) {
            Tier.XLARGE -> R.layout.widget_xlarge
            Tier.LARGE -> R.layout.widget_large
            Tier.MEDIUM -> R.layout.widget_medium
            Tier.COMPACT -> R.layout.widget_compact
          }

      val views = RemoteViews(context.packageName, layoutRes)

      views.setInt(R.id.bg_card, "setColorFilter", bg)
      views.setInt(R.id.log_button_bg, "setColorFilter", button)

      val active = streakWeeks > 0
      views.setImageViewResource(
          R.id.fire_icon,
          if (active) R.drawable.ic_widget_fire_active else R.drawable.ic_widget_fire_inactive,
      )
      views.setViewVisibility(R.id.fire_glow, if (active) View.VISIBLE else View.GONE)

      views.setTextViewText(R.id.streak_text, streakWeeks.toString())
      views.setTextColor(R.id.streak_text, if (active) accent else textMuted)
      views.setTextColor(R.id.streak_label, text)
      if (tier != Tier.COMPACT) {
        views.setTextColor(R.id.header_text, textMuted)
      }

      if (tier == Tier.LARGE || tier == Tier.XLARGE) {
        val weeksWord = if (bestStreakWeeks == 1) "week" else "weeks"
        views.setInt(R.id.best_chip_bg, "setColorFilter", surface)
        views.setTextViewText(R.id.best_text, "🏆 Best: $bestStreakWeeks $weeksWord")
        views.setTextColor(R.id.best_text, text)
        views.setTextViewText(
            R.id.best_ended_text,
            when {
              bestStreakWeeks == 0 -> ""
              bestStreakEnded.isEmpty() -> "ongoing 🔥"
              else -> "ended $bestStreakEnded"
            },
        )
        views.setTextColor(R.id.best_ended_text, textMuted)
      }

      views.setOnClickPendingIntent(R.id.widget_root, launch(context, "home"))
      views.setOnClickPendingIntent(R.id.log_button, launch(context, "logworkout"))
      if (tier == Tier.XLARGE) {
        val leagueName = widgetData.getString("league_name", "") ?: ""
        val leagueIcon = widgetData.getString("league_icon", "") ?: ""
        val nextWorkout = widgetData.getString("next_workout", "") ?: ""
        views.setInt(R.id.league_chip_bg, "setColorFilter", surface)
        views.setInt(R.id.next_chip_bg, "setColorFilter", surface)
        views.setTextViewText(
            R.id.league_text,
            if (leagueName.isEmpty()) "No league yet" else "$leagueIcon $leagueName League",
        )
        views.setTextViewText(
            R.id.next_workout_text,
            if (nextWorkout.isEmpty()) "Next: —" else "Next: $nextWorkout",
        )
        views.setTextColor(R.id.league_text, text)
        views.setTextColor(R.id.next_workout_text, text)
        views.setInt(R.id.bodyweight_button_bg, "setColorFilter", button2)
        views.setOnClickPendingIntent(R.id.bodyweight_button, launch(context, "logbodyweight"))
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun launch(context: Context, host: String) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("gymtracker://$host"),
        )
  }
}
