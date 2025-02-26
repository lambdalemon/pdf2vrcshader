// https://discussions.unity.com/t/sharing-is-caring-hiding-optional-material-parameters/594849
#if UNITY_EDITOR
using UnityEngine;
using UnityEditor;

public abstract class HideIfDrawer : MaterialPropertyDrawer
{
    protected string[] argValue;
    bool bElementHidden;
    protected abstract bool Enabled();

    public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
    {
        bElementHidden = false;
        for (int i = 0; i < editor.targets.Length; i++)
        {
            //material object that we're targetting...
            Material mat = editor.targets[i] as Material;
            if (mat != null)
            {
                //check for the dependencies:
                for (int j = 0; j < argValue.Length; j++)
                    bElementHidden |= mat.IsKeywordEnabled(argValue[j]) == Enabled();
            }
        }

        if (!bElementHidden)
            editor.DefaultShaderProperty(prop, label);
    }

    //We need to override the height so it's not adding any extra (unfortunately texture drawers will still add an extra bit of padding regardless):
    public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
    {
        return -EditorGUIUtility.standardVerticalSpacing;
    }

}

public class HideIfDisabledDrawer : HideIfDrawer
{
    protected override bool Enabled() {
        return false;
    }

    //constructor permutations -- params doesn't seem to work for property drawer inputs :( -----------
    public HideIfDisabledDrawer(string name1)
    {
        argValue = new string[] { name1 };
    }

    public HideIfDisabledDrawer(string name1, string name2)
    {
        argValue = new string[] { name1, name2 };
    }

    public HideIfDisabledDrawer(string name1, string name2, string name3)
    {
        argValue = new string[] { name1, name2, name3 };
    }

    public HideIfDisabledDrawer(string name1, string name2, string name3, string name4)
    {
        argValue = new string[] { name1, name2, name3, name4 };
    }
}

public class HideIfEnabledDrawer : HideIfDrawer
{
    protected override bool Enabled() {
        return true;
    }

    //constructor permutations -- params doesn't seem to work for property drawer inputs :( -----------
    public HideIfEnabledDrawer(string name1)
    {
        argValue = new string[] { name1 };
    }

    public HideIfEnabledDrawer(string name1, string name2)
    {
        argValue = new string[] { name1, name2 };
    }

    public HideIfEnabledDrawer(string name1, string name2, string name3)
    {
        argValue = new string[] { name1, name2, name3 };
    }

    public HideIfEnabledDrawer(string name1, string name2, string name3, string name4)
    {
        argValue = new string[] { name1, name2, name3, name4 };
    }
}
#endif
