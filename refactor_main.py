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

classes_to_extract = {
    'DigitalScoreScreen': 'lib/features/hymnal/presentation/digital_score_screen.dart',
    'OutputScreen': 'lib/features/projection/presentation/output_screen.dart',
    'ProjectionOutputView': 'lib/features/projection/presentation/projection_output_view.dart',
    'LecternReaderScreen': 'lib/features/hymnal/presentation/lectern_reader_screen.dart',
    'EntryReaderModal': 'lib/features/hymnal/presentation/entry_reader_modal.dart'
}

imports_hymnal = """import 'package:flutter/material.dart';
import '../../../content.dart';
import '../../../glass.dart';
import '../../../audio_handler.dart';
"""

imports_projection = """import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../appearance.dart';
import '../../../slide_view.dart';
import '../../../motion_background_view.dart';
"""

for cls, path in classes_to_extract.items():
    start, end = get_class_lines(cls)
    if start != -1:
        # Also extract state class if exists
        state_cls = f'_{cls}State'
        s_start, s_end = get_class_lines(state_cls)
        
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            if 'hymnal' in path:
                f.write(imports_hymnal)
            else:
                f.write(imports_projection)
            
            f.write("".join(lines[start:end+1]))
            if s_start != -1:
                f.write("\n")
                f.write("".join(lines[s_start:s_end+1]))

# Remove from main.dart
to_remove = []
for cls in classes_to_extract.keys():
    start, end = get_class_lines(cls)
    if start != -1:
        to_remove.extend(range(start, end+1))
        state_cls = f'_{cls}State'
        s_start, s_end = get_class_lines(state_cls)
        if s_start != -1:
            to_remove.extend(range(s_start, s_end+1))

new_main = [line for i, line in enumerate(lines) if i not in to_remove]
with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_main)

print("Extracted standalone classes.")
