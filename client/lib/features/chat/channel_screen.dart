import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/message_provider.dart';
import '../../core/channel_provider.dart';
import '../../core/settings_provider.dart';
import '../home/rainbow_builder.dart';

/// Full channel view — header, message list, and message input.
class ChannelScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String channelId;

  const ChannelScreen({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Fetch messages when entering channel
    Future.microtask(() {
      ref.read(messagesProvider.notifier).fetchMessages(widget.channelId);
    });
  }

  @override
  void didUpdateWidget(covariant ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      ref.read(messagesProvider.notifier).fetchMessages(widget.channelId);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messagesProvider);
    final auth = ref.watch(authProvider);
    final channelsState = ref.watch(channelsProvider);
    final settings = ref.watch(settingsProvider);

    // Find channel name
    final channelName = channelsState.channels
            .where((c) => c.id == widget.channelId)
            .map((c) => c.name)
            .firstOrNull ??
        'channel';

    return Column(
      children: [
        // ─── Channel Header ───────────────────────────────────────────
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(
              horizontal: AntarcticomTheme.spacingMd),
          decoration: BoxDecoration(
            color: AntarcticomTheme.bgPrimary
                .withValues(alpha: settings.sidebarOpacity),
          ),
          child: Row(
            children: [
              const Icon(Icons.tag,
                  size: 20, color: AntarcticomTheme.textMuted),
              const SizedBox(width: AntarcticomTheme.spacingSm),
              Text(
                channelName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AntarcticomTheme.textPrimary,
                    ),
              ),
            ],
          ),
        ),

        // ─── Messages ─────────────────────────────────────────────────
        Expanded(
          child: msgState.isLoading
              ? Center(
                  child: RainbowBuilder(
                      enabled: settings.rainbowMode,
                      builder: (context, color) {
                        return CircularProgressIndicator(
                          color: settings.rainbowMode
                              ? color
                              : AntarcticomTheme.accentPrimary,
                        );
                      }),
                )
              : msgState.error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              color: AntarcticomTheme.textMuted, size: 48),
                          const SizedBox(height: AntarcticomTheme.spacingSm),
                          Text(msgState.error!,
                              style:
                                  TextStyle(color: AntarcticomTheme.textMuted)),
                          const SizedBox(height: AntarcticomTheme.spacingMd),
                          TextButton(
                            onPressed: () => ref
                                .read(messagesProvider.notifier)
                                .fetchMessages(widget.channelId),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : msgState.messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  color: AntarcticomTheme.textMuted, size: 48),
                              const SizedBox(
                                  height: AntarcticomTheme.spacingSm),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                    color: AntarcticomTheme.textMuted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Be the first to say something!',
                                style: TextStyle(
                                    color: AntarcticomTheme.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          color: AntarcticomTheme.bgPrimary
                              .withOpacity(settings.backgroundOpacity),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              vertical: AntarcticomTheme.spacingMd,
                            ),
                            itemCount: msgState.messages.length,
                            itemBuilder: (context, index) {
                              final msg = msgState.messages[index];
                              final isOwn = msg.authorId == auth.user?.id;
                              return _MessageBubble(
                                message: msg,
                                isOwn: isOwn,
                                authorName: isOwn
                                    ? (auth.user?.displayName ?? 'You')
                                    : msg.authorId.substring(0, 8),
                              );
                            },
                          ),
                        ),
        ),

        // ─── Message Input ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(AntarcticomTheme.spacingMd),
          decoration: BoxDecoration(
            color:
                AntarcticomTheme.bgPrimary.withOpacity(settings.sidebarOpacity),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AntarcticomTheme.bgTertiary.withOpacity(0.8),
                    borderRadius:
                        BorderRadius.circular(AntarcticomTheme.radiusMd),
                  ),
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: AntarcticomTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Message #$channelName',
                      hintStyle:
                          const TextStyle(color: AntarcticomTheme.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AntarcticomTheme.spacingMd,
                        vertical: AntarcticomTheme.spacingSm,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: AntarcticomTheme.spacingSm),
              RainbowBuilder(
                  enabled: settings.rainbowMode,
                  builder: (context, color) {
                    return IconButton(
                      onPressed: _isSending ? null : _sendMessage,
                      icon: _isSending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: settings.rainbowMode
                                      ? color
                                      : AntarcticomTheme.accentPrimary),
                            )
                          : const Icon(Icons.send_rounded),
                      color:
                          settings.rainbowMode ? color : settings.accentColor,
                      splashRadius: 20,
                    );
                  }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    final success = await ref
        .read(messagesProvider.notifier)
        .sendMessage(widget.channelId, text);

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        // Scroll to bottom
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }
}

// ─── Message Bubble ─────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MessageInfo message;
  final bool isOwn;
  final String authorName;

  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.authorName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AntarcticomTheme.spacingMd,
        vertical: 2,
      ),
      child: MouseRegion(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AntarcticomTheme.spacingMd,
            vertical: AntarcticomTheme.spacingSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AntarcticomTheme.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: isOwn
                      ? AntarcticomTheme.accentGradient
                      : const LinearGradient(
                          colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                        ),
                  borderRadius:
                      BorderRadius.circular(AntarcticomTheme.radiusFull),
                ),
                child: Center(
                  child: Text(
                    authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AntarcticomTheme.spacingSm),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          authorName,
                          style: TextStyle(
                            color: isOwn
                                ? AntarcticomTheme.accentSecondary
                                : const Color(0xFF7C8CFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: AntarcticomTheme.spacingSm),
                        Text(
                          message.formattedTime,
                          style: const TextStyle(
                            color: AntarcticomTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: AntarcticomTheme.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
