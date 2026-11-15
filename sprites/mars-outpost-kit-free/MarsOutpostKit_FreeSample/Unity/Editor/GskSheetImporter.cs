// Mars Outpost Kit: slices a sprite sheet from its JSON and builds an AnimationClip per animation.
// Put this file in Assets/Editor. Select one or more *_sheet.json files, then
// Tools > Mars Outpost Kit > Slice Sheets and Make Animations.
// Works with Unity 2021.3 and newer, no packages needed.
#if UNITY_EDITOR
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class GskSheetImporter
{
    [System.Serializable] class Rect4 { public int x, y, w, h; }
    [System.Serializable] class Size2 { public int w, h; }
    [System.Serializable] class Frame { public string filename; public Rect4 frame; public int duration; }
    [System.Serializable] class Tag { public string name; public int from, to; public string direction; }
    [System.Serializable] class Meta { public string image; public Size2 size; public Tag[] frameTags; }
    [System.Serializable] class Sheet { public Frame[] frames; public Meta meta; }

    const float PixelsPerUnit = 32f;
    static readonly string[] Loops = { "thrust", "pulse", "loop", "idle", "fly" };

    [MenuItem("Tools/Mars Outpost Kit/Slice Sheets and Make Animations")]
    static void Run()
    {
        int done = 0;
        foreach (var obj in Selection.objects)
        {
            string jsonPath = AssetDatabase.GetAssetPath(obj);
            if (!jsonPath.EndsWith(".json")) continue;
            var sheet = JsonUtility.FromJson<Sheet>(File.ReadAllText(jsonPath));
            if (sheet == null || sheet.frames == null || sheet.meta == null) continue;
            string dir = Path.GetDirectoryName(jsonPath).Replace('\\', '/');
            string pngPath = dir + "/" + Path.GetFileNameWithoutExtension(jsonPath) + ".png";
            if (!File.Exists(pngPath)) pngPath = dir + "/" + sheet.meta.image;
            var imp = AssetImporter.GetAtPath(pngPath) as TextureImporter;
            if (imp == null) { Debug.LogWarning("No texture next to " + jsonPath); continue; }

            imp.textureType = TextureImporterType.Sprite;
            imp.spriteImportMode = SpriteImportMode.Multiple;
            imp.filterMode = FilterMode.Point;
            imp.mipmapEnabled = false;
            imp.textureCompression = TextureImporterCompression.Uncompressed;
            imp.spritePixelsPerUnit = PixelsPerUnit;
            int H = sheet.meta.size.h;
            var metas = new List<SpriteMetaData>();
            foreach (var f in sheet.frames)
            {
                metas.Add(new SpriteMetaData
                {
                    name = f.filename,
                    rect = new Rect(f.frame.x, H - f.frame.y - f.frame.h, f.frame.w, f.frame.h),
                    alignment = (int)SpriteAlignment.BottomCenter,
                    pivot = new Vector2(0.5f, 0f)
                });
            }
#pragma warning disable 618
            imp.spritesheet = metas.ToArray();
#pragma warning restore 618
            imp.SaveAndReimport();

            var sprites = new Dictionary<string, Sprite>();
            foreach (var a in AssetDatabase.LoadAllAssetsAtPath(pngPath))
                if (a is Sprite s) sprites[s.name] = s;

            string clipDir = dir + "/Animations";
            if (!AssetDatabase.IsValidFolder(clipDir)) AssetDatabase.CreateFolder(dir, "Animations");
            string baseName = Path.GetFileNameWithoutExtension(jsonPath).Replace("_sheet", "");
            if (sheet.meta.frameTags == null) continue;
            foreach (var tag in sheet.meta.frameTags)
            {
                var clip = new AnimationClip { frameRate = 60f };
                var keys = new List<ObjectReferenceKeyframe>();
                float t = 0f;
                for (int i = tag.from; i <= tag.to && i < sheet.frames.Length; i++)
                {
                    Sprite sp;
                    if (!sprites.TryGetValue(sheet.frames[i].filename, out sp)) continue;
                    keys.Add(new ObjectReferenceKeyframe { time = t, value = sp });
                    t += Mathf.Max(1, sheet.frames[i].duration) / 1000f;
                }
                if (keys.Count == 0) continue;
                keys.Add(new ObjectReferenceKeyframe { time = t, value = keys[keys.Count - 1].value });
                var binding = EditorCurveBinding.PPtrCurve("", typeof(SpriteRenderer), "m_Sprite");
                AnimationUtility.SetObjectReferenceCurve(clip, binding, keys.ToArray());
                var settings = AnimationUtility.GetAnimationClipSettings(clip);
                settings.loopTime = System.Array.IndexOf(Loops, tag.name) >= 0;
                AnimationUtility.SetAnimationClipSettings(clip, settings);
                AssetDatabase.CreateAsset(clip, clipDir + "/" + baseName + "_" + tag.name + ".anim");
            }
            done++;
        }
        AssetDatabase.SaveAssets();
        Debug.Log("Mars Outpost Kit: sliced " + done + " sheet(s).");
    }
}
#endif
