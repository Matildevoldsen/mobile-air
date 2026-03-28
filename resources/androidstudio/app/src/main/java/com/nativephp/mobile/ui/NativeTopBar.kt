package com.nativephp.mobile.ui

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

private const val TAG = "NativeTopBar"

/**
 * Material3 Top App Bar that renders from Laravel NativeUI state
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeTopBar(
    onMenuClick: () -> Unit,
    onNavigate: (String) -> Unit = {}
) {
    val topBarData by NativeUIState.topBarData
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // Only render if we have top bar data
    if (topBarData == null) {
        return
    }

    val data = topBarData!!
    val backgroundColor = data.backgroundColor?.let { parseColor(it) }
    val textColor = data.textColor?.let { parseColor(it) }
    val actions = data.children?.mapNotNull { it.data } ?: emptyList()

    // Split actions into visible (max 3) and overflow
    val visibleActions = actions.take(3)
    val overflowActions = actions.drop(3)
    val showOverflowMenu = remember { mutableStateOf(false) }

    fun handleAction(action: TopBarAction) {
        Log.d(TAG, "⚡ Action clicked: ${action.label ?: action.id}")
        action.url?.let { url ->
            if (isExternalUrl(url)) {
                Log.d(TAG, "🌐 Opening external URL in browser: $url")
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    context.startActivity(intent)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open external URL: $url", e)
                }
            } else {
                Log.d(TAG, "📱 Opening internal URL in WebView: $url")
                onNavigate(url)
            }
        }
        action.event?.let {
            Log.d(TAG, "📢 Dispatching event: $it")
        }
    }

    TopAppBar(
        modifier = Modifier.windowInsetsPadding(WindowInsets.statusBars),
        title = {
            Column {
                Text(
                    text = data.title,
                    color = textColor ?: MaterialTheme.colorScheme.onSurface
                )
                data.subtitle?.let { subtitle ->
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = textColor?.copy(alpha = 0.7f) ?: MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                    )
                }
            }
        },
        navigationIcon = {
            if (data.showNavigationIcon == true) {
                IconButton(onClick = {
                    Log.d(TAG, "🍔 Navigation icon clicked")
                    if (NativeUIState.drawerState != null) {
                        scope.launch {
                            NativeUIState.drawerState?.open()
                            Log.d(TAG, "✅ Drawer opened!")
                        }
                    } else {
                        onNavigate("/native/open-sidebar")
                    }
                    onMenuClick()
                }) {
                    MaterialIcon(
                        name = "menu",
                        contentDescription = "Menu",
                        tint = textColor ?: MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        },
        actions = {
            // Render visible actions (max 3)
            visibleActions.forEach { action ->
                if (action.showLabel == true && !action.label.isNullOrBlank()) {
                    TextButton(
                        onClick = { handleAction(action) },
                        modifier = Modifier.widthIn(max = 180.dp),
                    ) {
                        Row {
                            if (action.icon.isNotBlank()) {
                                MaterialIcon(
                                    name = action.icon,
                                    contentDescription = action.label ?: action.id,
                                    size = 18.dp,
                                    tint = textColor ?: MaterialTheme.colorScheme.onSurface,
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                            }

                            Text(
                                text = action.label,
                                color = textColor ?: MaterialTheme.colorScheme.onSurface,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                } else {
                    IconButton(
                        onClick = { handleAction(action) }
                    ) {
                        MaterialIcon(
                            name = action.icon,
                            contentDescription = action.label ?: action.id,
                            tint = textColor ?: MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }

            // Overflow menu if more than 3 actions
            if (overflowActions.isNotEmpty()) {
                IconButton(onClick = { showOverflowMenu.value = true }) {
                    MaterialIcon(
                        name = "more_vert",
                        contentDescription = "More options",
                        tint = textColor ?: MaterialTheme.colorScheme.onSurface
                    )
                }

                DropdownMenu(
                    expanded = showOverflowMenu.value,
                    onDismissRequest = { showOverflowMenu.value = false }
                ) {
                    overflowActions.forEach { action ->
                        DropdownMenuItem(
                            text = { Text(action.label ?: action.id) },
                            onClick = {
                                showOverflowMenu.value = false
                                handleAction(action)
                            },
                            leadingIcon = {
                                MaterialIcon(
                                    name = action.icon,
                                    contentDescription = action.label ?: action.id
                                )
                            }
                        )
                    }
                }
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = backgroundColor ?: MaterialTheme.colorScheme.surface,
            titleContentColor = textColor ?: MaterialTheme.colorScheme.onSurface,
            navigationIconContentColor = textColor ?: MaterialTheme.colorScheme.onSurface
        )
    )
}

/**
 * Check if a URL is external (not a relative path or localhost)
 */
private fun isExternalUrl(url: String): Boolean {
    return (url.startsWith("http://") || url.startsWith("https://"))
            && !url.contains("127.0.0.1")
            && !url.contains("localhost")
}

/**
 * Parse hex color string to Color
 */
private fun parseColor(colorString: String): Color? {
    return try {
        val hex = colorString.removePrefix("#")
        when (hex.length) {
            6 -> Color(android.graphics.Color.parseColor("#$hex"))
            8 -> Color(android.graphics.Color.parseColor("#$hex"))
            else -> null
        }
    } catch (e: Exception) {
        null
    }
}
