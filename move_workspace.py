import os

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

def get_class_lines(class_name):
    start = -1
    for i, line in enumerate(lines):
        if line.startswith(f'class {class_name}'):
            start = i
            break
    if start == -1: return -1, -1
    
    braces = 0
    end = -1
    for i in range(start, len(lines)):
        braces += lines[i].count('{')
        braces -= lines[i].count('}')
        if braces == 0 and lines[i].count('}') > 0:
            end = i
            break
    return start, end

classes = ['WorkspaceLoader', '_WorkspaceLoaderState', 'Workspace', 'WorkspaceState']

start_idx = get_class_lines('WorkspaceLoader')[0]
end_idx = get_class_lines('WorkspaceState')[1]

if start_idx != -1 and end_idx != -1:
    workspace_lines = lines[start_idx:end_idx+1]
    
    # Write workspace.dart
    os.makedirs('lib/features/workspace', exist_ok=True)
    imports = """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:marquee/marquee.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../content.dart';
import '../../slide_view.dart';
import '../../appearance.dart';
import '../../glass.dart';
import '../../playback.dart';
import '../../cult_files.dart';
import '../../media_store.dart';
import '../../motion_background_view.dart';
import '../../countdown.dart';
import '../../stage_display.dart';
import '../../remote_server.dart';
import '../../remote_client_screen.dart';
import '../../audio_manager_screen.dart';
import '../../service_templates.dart';
import '../../main.dart' show appThemeMode, appVisualEffectsMode, VisualEffectsMode, VisualEffectsScope, digitalScorePages, globalAudioHandler, serviceTemplateIcons, serviceTemplateIconLabels, serviceSectionIcons;
import '../meet_service/presentation/live_meet_card.dart';
import '../hymnal/presentation/digital_score_screen.dart';
import '../hymnal/presentation/entry_reader_modal.dart';
"""
    with open('lib/features/workspace/workspace.dart', 'w', encoding='utf-8') as f:
        f.write(imports + "\n")
        f.writelines(workspace_lines)
    
    # Remove from main.dart
    new_main = lines[:start_idx] + lines[end_idx+1:]
    # add import to main.dart
    new_main.insert(40, "import 'features/workspace/workspace.dart';\n")
    
    with open('lib/main.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_main)
    print("Successfully moved Workspace to features/workspace/workspace.dart")
else:
    print("Could not find classes")
