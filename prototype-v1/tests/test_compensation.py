import unittest
from compensation import distance, position_to_gains

class CompensationTests(unittest.TestCase):
    speakers = ((1., .5), (3., .5))
    refs = (distance((2, 2), speakers[0]), distance((2, 2), speakers[1]))

    def calculate(self, p):
        return position_to_gains(p, self.speakers, self.refs)

    def test_reference(self):
        self.assertEqual(self.calculate((2, 2)).gains, (.25, .25))

    def test_farther_and_closer(self):
        self.assertGreater(self.calculate((2, 3)).requested[0], .25)
        self.assertLess(self.calculate((1, 1)).requested[0], .25)

    def test_symmetry(self):
        self.assertEqual(self.calculate((.5, 2)).gains, self.calculate((3.5, 2)).gains[::-1])

    def test_minimum(self):
        self.assertEqual(distance((1, .5), (1, .5)), .25)
        result = position_to_gains((1, .5), self.speakers, (.25, 2))
        self.assertEqual(result.gains, (.25, .25))

    def test_limit(self):
        result = self.calculate((100, 100))
        self.assertTrue(result.limited)
        self.assertEqual(result.gains, (1, 1))
        self.assertTrue(all(g > 1 for g in result.requested))

    def test_branch_amplitude_constant(self):
        for p in ((2, 2), (1, 1), (4, 4)):
            result = self.calculate(p)
            for g, d, ref in zip(result.gains, result.distances, self.refs):
                self.assertAlmostEqual(g / d, .25 / ref)

    def test_invalid(self):
        with self.assertRaises(ValueError):
            self.calculate((float('nan'), 2))
        with self.assertRaises(ValueError):
            position_to_gains((2, 2), self.speakers, (0, 1))

if __name__ == '__main__':
    unittest.main()
