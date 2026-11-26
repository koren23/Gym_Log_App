package com.korengym.gym_tracker

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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

  companion object {
    private const val TIER_MEDIUM_MIN_HEIGHT_DP = 110
    private const val TIER_LARGE_MIN_HEIGHT_DP = 180

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: SharedPreferences,
    ) {
      val streakWeeks = widgetData.getInt("streak_weeks", 0)
      val bestStreakWeeks = widgetData.getInt("best_streak_weeks", 0)

      val minHeightDp =
          appWidgetManager.getAppWidgetOptions(appWidgetId)
              .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, TIER_MEDIUM_MIN_HEIGHT_DP)

      val layoutRes =
          when {
            minHeightDp >= TIER_LARGE_MIN_HEIGHT_DP -> R.layout.widget_large
            minHeightDp >= TIER_MEDIUM_MIN_HEIGHT_DP -> R.layout.widget_medium
            else -> R.layout.widget_compact
          }

      val views = RemoteViews(context.packageName, layoutRes)
      views.setTextViewText(R.id.streak_text, streakWeeks.toString())
      if (layoutRes == R.layout.widget_large) {
        views.setTextViewText(R.id.best_text, "Best: ${bestStreakWeeks}wk 🏆")
      }

      val launchIntent =
          HomeWidgetLaunchIntent.getActivity(
              context,
              MainActivity::class.java,
              Uri.parse("gymtracker://logworkout"),
          )
      views.setOnClickPendingIntent(R.id.log_button, launchIntent)

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }
}
