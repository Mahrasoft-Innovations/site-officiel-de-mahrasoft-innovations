import os
from PIL import Image

STATIC_IMG_DIR = "Backend/app/static/img"
QUALITY = 85  # Qualité WebP (0-100)

def convert_to_webp(input_path, output_path, sizes=None):
    """Convertit une image en WebP, avec possibilité de redimensionnement."""
    try:
        with Image.open(input_path) as img:
            if sizes:
                for width, suffix in sizes:
                    img_copy = img.copy()
                    img_copy.thumbnail((width, width))
                    out = output_path.replace('.webp', f'-{width}.webp') if suffix else output_path
                    img_copy.save(out, 'webp', quality=QUALITY, method=6)
                    print(f"✅ {out}")
            else:
                img.save(output_path, 'webp', quality=QUALITY, method=6)
                print(f"✅ {output_path}")
    except Exception as e:
        print(f"❌ Erreur sur {input_path} : {e}")

if __name__ == "__main__":
    # Liste des fichiers à convertir (nom de base sans extension)
    files_to_convert = [
        ("img11.jpeg", [(600, True), (1200, True)]),  # srcset
        ("cours_1.jpeg", None),
        ("cours_10.jpeg", None),
        ("logomahrasoftAcademia.png", None),
        ("logo_Mahrasouk.png", None),
    ]

    for filename, sizes in files_to_convert:
        base, ext = os.path.splitext(filename)
        input_path = os.path.join(STATIC_IMG_DIR, filename)
        output_path = os.path.join(STATIC_IMG_DIR, base + '.webp')

        if not os.path.exists(input_path):
            print(f"⚠️ Fichier source introuvable : {input_path}")
            continue

        convert_to_webp(input_path, output_path, sizes)