
package ay.classifier;

import ay.model.*;
import jakarta.enterprise.context.ApplicationScoped;

@Single
@ApplicationScoped
public class SimpleClassifier implements Classifier {

    // ...existing code...

    /**
     * Classifies a value as PII or not, returning a ranking score.
     * 
     * @param value the string value to classify
     * @return a float closer to Ranking.HIGHEST if PII, Ranking.LOWEST if not
     */
    public Ranking rank(Cell cell) {
        Object value = cell.value();
        if (value == null || value.toString().isBlank())
            return Ranking.of(Rankings.LOW.getValue());
        var valueStr = value.toString().trim();
        if (singleNumber(valueStr)) {
            return Ranking.of(Rankings.LOW.getValue());
        }
        var isPII = false ||
            isLikelyEmail(valueStr) ||
            isLikelyPhone(valueStr) ||
            isLikelySSN(valueStr) ||
            isLikelyFullName(valueStr) ||
            isLikelyAddress(valueStr);
        var rank = isPII ? Rankings.HIGH.getValue() : Rankings.LOW.getValue();
        return Ranking.of(rank);
    }

    private boolean singleNumber(String valueStr) {
        // Accepts strings that are only digits, possibly with spaces, dashes, or parentheses
        String cleaned = valueStr.replaceAll("[\\s\\-()]", "");
        return cleaned.matches("^\\d{1,5}$");
    }

    // Heuristic: likely a full name (title, first, last, suffix)
    private boolean isLikelyFullName(String value) {
        // Must contain at least one space (first and last name)
        if (!value.contains(" ")) return false;
        // Only a full name if starts with a title or ends with a suffix
        boolean hasTitle = value.matches("^(Mr\\.?|Ms\\.?|Mrs\\.?|Dr\\.?|Miss) .+");
        boolean hasSuffix = value.matches(".+ (Jr\\.|Sr\\.|IV|III|II|PhD|DDS|MD)$");
        if (!hasTitle && !hasSuffix) return false;
        // Accepts names with titles or suffixes, e.g., 'Ms. Jane Doe', 'John Smith Jr.'
        return value.matches(
                "^(Mr\\.?|Ms\\.?|Mrs\\.?|Dr\\.?|Miss)? ?[A-Z][a-z]+( [A-Z][a-z]+)*(( [A-Z][a-z]+)?( (Jr\\.|Sr\\.|IV|III|II|PhD|DDS|MD))?)?$")
                && value.length() < 60;
    }

    // Heuristic: likely an address (number + street/road/avenue/etc)
    private static boolean isLikelyAddress(String value) {
        String lower = value.toLowerCase();
        return lower.matches(".*\\d+.*") && (lower.contains("street") || lower.contains("st ")
                || lower.contains("avenue") || lower.contains("ave") || lower.contains("road") || lower.contains("rd ")
                || lower.contains("blvd") || lower.contains("lane") || lower.contains("ln ") || lower.contains("harbor")
                || lower.contains("summit") || lower.contains("plaza") || lower.contains("ways")
                || lower.contains("passage") || lower.contains("isle") || lower.contains("highway")
                || lower.contains("circle") || lower.contains("mountain") || lower.contains("grove")
                || lower.contains("court") || lower.contains("fork") || lower.contains("ramp")
                || lower.contains("turnpike") || lower.contains("expressway") || lower.contains("boulevard")
                || lower.contains("flat") || lower.contains("spurs") || lower.contains("estate")
                || lower.contains("dam") || lower.contains("radial") || lower.contains("corners")
                || lower.contains("terrace") || lower.contains("garden") || lower.contains("greens")
                || lower.contains("key") || lower.contains("light") || lower.contains("plain") || lower.contains("ru")
                || lower.contains("summit") || lower.contains("cove") || lower.contains("island")
                || lower.contains("branch") || lower.contains("alley") || lower.contains("walk")
                || lower.contains("centers") || lower.contains("ferry") || lower.contains("extensions")
                || lower.contains("glen") || lower.contains("shoal") || lower.contains("squares")
                || lower.contains("village") || lower.contains("hills") || lower.contains("knolls")
                || lower.contains("ridges") || lower.contains("squares") || lower.contains("parks")
                || lower.contains("estate") || lower.contains("summit"));
    }

    private static boolean isLikelyParentName(String value) {
        // Accepts single capitalized names, not too long, not a color or instrument
        return value.matches("^[A-Z][a-zA-Z]{2,20}$");
    }

 

    private boolean isLikelyEmail(String value) {
        return value.matches("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$");
    }

    private boolean isLikelyPhone(String value) {
        // Simple phone pattern: digits, optional +, spaces, dashes, parentheses
        return value.matches("^(\\+?\\d{1,3}[-.\\s]?)?(\\(?\\d{2,4}\\)?[-.\\s]?)?\\d{3,4}[-.\\s]?\\d{3,4}$");
    }

    private boolean isLikelySSN(String value) {
        // US SSN: 3-2-4 digits
        return value.matches("^\\d{3}-\\d{2}-\\d{4}$");
    }

}
