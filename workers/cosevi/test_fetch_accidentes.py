import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from fetch_accidentes import aggregate_records, parse_records


class CoseviParserTests(unittest.TestCase):
    def test_parses_official_semicolon_csv_and_aggregates_same_category(self):
        csv_text = (
            "Clase de accidente;Tipo de accidente;Año;Provincia ;Cantón;Distrito\n"
            "Solo heridos leves;Colisión;2024;San José;San José;Carmen\n"
            "Solo heridos leves;Colisión;2024;San José;San José;Carmen\n"
        )

        records = parse_records(csv_text)
        aggregated, unmatched = aggregate_records(records, {"SAN JOSE": (1, "101")})

        self.assertEqual(unmatched, {})
        self.assertEqual(len(aggregated), 1)
        row = next(iter(aggregated.values()))
        self.assertEqual(row["cantidad"], 2)
        self.assertEqual(row["anio"], 2024)
        self.assertEqual(row["canton_id"], 1)

    def test_rejects_csv_missing_required_columns(self):
        with self.assertRaisesRegex(ValueError, "columnas requeridas"):
            parse_records("Año;Cantón\n2024;San José\n")
