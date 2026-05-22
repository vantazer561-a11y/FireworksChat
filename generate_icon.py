"""Generate FireworksChat app icon - a stylized firework/spark chat bubble."""
from PIL import Image, ImageDraw, ImageFont
import math
import os

def generate_icon(size=1024):
    """Generate a 1024x1024 app icon."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Background gradient (dark blue to purple)
    for y in range(size):
        ratio = y / size
        r = int(20 + ratio * 40)
        g = int(10 + ratio * 15)
        b = int(60 + ratio * 80)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))
    
    # Draw rounded rectangle background
    # (iOS clips to rounded rect automatically, but let's make it look good)
    
    center_x, center_y = size // 2, size // 2
    
    # Draw firework sparks emanating from center
    spark_colors = [
        (255, 140, 0),    # Orange
        (255, 200, 50),   # Gold
        (255, 100, 50),   # Red-orange
        (255, 220, 100),  # Light gold
        (255, 160, 30),   # Deep orange
    ]
    
    # Main burst - large sparks
    num_sparks = 12
    for i in range(num_sparks):
        angle = (2 * math.pi * i / num_sparks) - math.pi / 2
        color = spark_colors[i % len(spark_colors)]
        
        # Spark line
        inner_r = size * 0.12
        outer_r = size * 0.35
        x1 = center_x + math.cos(angle) * inner_r
        y1 = center_y + math.sin(angle) * inner_r
        x2 = center_x + math.cos(angle) * outer_r
        y2 = center_y + math.sin(angle) * outer_r
        
        # Draw tapered spark
        for t in range(20):
            frac = t / 20.0
            px = x1 + (x2 - x1) * frac
            py = y1 + (y2 - y1) * frac
            width = int(8 * (1 - frac) + 2)
            alpha = int(255 * (1 - frac * 0.5))
            draw.ellipse(
                [px - width, py - width, px + width, py + width],
                fill=(*color, alpha)
            )
    
    # Secondary burst - smaller sparks
    num_small = 24
    for i in range(num_small):
        angle = (2 * math.pi * i / num_small) + math.pi / num_small
        color = spark_colors[i % len(spark_colors)]
        
        inner_r = size * 0.15
        outer_r = size * 0.25
        x1 = center_x + math.cos(angle) * inner_r
        y1 = center_y + math.sin(angle) * inner_r
        x2 = center_x + math.cos(angle) * outer_r
        y2 = center_y + math.sin(angle) * outer_r
        
        for t in range(10):
            frac = t / 10.0
            px = x1 + (x2 - x1) * frac
            py = y1 + (y2 - y1) * frac
            width = int(4 * (1 - frac) + 1)
            alpha = int(200 * (1 - frac * 0.6))
            draw.ellipse(
                [px - width, py - width, px + width, py + width],
                fill=(*color, alpha)
            )
    
    # Dots at spark tips
    for i in range(num_sparks):
        angle = (2 * math.pi * i / num_sparks) - math.pi / 2
        color = spark_colors[i % len(spark_colors)]
        outer_r = size * 0.36
        x = center_x + math.cos(angle) * outer_r
        y = center_y + math.sin(angle) * outer_r
        dot_size = 6
        draw.ellipse(
            [x - dot_size, y - dot_size, x + dot_size, y + dot_size],
            fill=(*color, 255)
        )
    
    # Central glow
    for r in range(int(size * 0.12), 0, -1):
        alpha = int(180 * (1 - r / (size * 0.12)))
        draw.ellipse(
            [center_x - r, center_y - r, center_x + r, center_y + r],
            fill=(255, 200, 80, alpha)
        )
    
    # Chat bubble shape in the center (small, subtle)
    bubble_size = size * 0.18
    bx, by = center_x, center_y
    draw.rounded_rectangle(
        [bx - bubble_size, by - bubble_size * 0.7, bx + bubble_size, by + bubble_size * 0.7],
        radius=int(bubble_size * 0.4),
        fill=(255, 255, 255, 200)
    )
    # Bubble tail
    tail_points = [
        (bx - bubble_size * 0.3, by + bubble_size * 0.5),
        (bx - bubble_size * 0.6, by + bubble_size * 1.0),
        (bx, by + bubble_size * 0.7),
    ]
    draw.polygon(tail_points, fill=(255, 255, 255, 200))
    
    # Three dots in the bubble (typing indicator)
    dot_r = int(bubble_size * 0.1)
    for dx in [-1, 0, 1]:
        dot_x = bx + dx * bubble_size * 0.3
        dot_y = by
        draw.ellipse(
            [dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r],
            fill=(60, 30, 100, 220)
        )
    
    return img


def save_icons():
    """Save icon in all required sizes for iOS."""
    icon = generate_icon(1024)
    
    # iOS icon sizes needed
    sizes = [1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20]
    
    output_dir = "FireworksChat/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(output_dir, exist_ok=True)
    
    # Save 1024x1024 (App Store)
    icon_rgb = Image.new('RGB', (1024, 1024), (20, 10, 60))
    icon_rgb.paste(icon, mask=icon.split()[3])
    icon_rgb.save(os.path.join(output_dir, "icon_1024.png"))
    
    # Save other sizes
    for s in sizes:
        if s == 1024:
            continue
        resized = icon_rgb.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(output_dir, f"icon_{s}.png"))
    
    # Generate Contents.json
    contents = {
        "images": [
            {"filename": "icon_1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1}
    }
    
    import json
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    
    print(f"Icons generated in {output_dir}/")
    print("Generated sizes:", [f"{s}x{s}" for s in sizes])


if __name__ == "__main__":
    save_icons()
